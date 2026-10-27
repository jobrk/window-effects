// Adapted from yabai dd845723416f5fe92af49fad5ebab00369e07edd; see vendor/yabai-LICENSE.txt.
#include <Cocoa/Cocoa.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>

#include <ptrauth.h>
#if !defined(__arm64__) || !__has_feature(ptrauth_calls)
#error "Build the Dock loader with -arch arm64e, not arm64"
#endif
kern_return_t (*_thread_convert_thread_state)(thread_act_t thread, int direction,
                                              thread_state_flavor_t flavor, thread_state_t in_state,
                                              mach_msg_type_number_t in_stateCnt,
                                              thread_state_t out_state,
                                              mach_msg_type_number_t *out_stateCnt);

// Fixed path: the sudoers rule must never permit loading caller-selected code.
static char *payload_path = "/Library/Application Support/WindowEffects/payload.dylib";

// The arm64e injection path credits Jeremy Legendre (https://github.com/jslegendre).
//
// A Mach thread is not a normal pthread: the injected stub first creates a
// pthread, which calls dlopen(payload_path). The bootstrap thread then spins
// with a sentinel in x0 so the loader can stop it without interrupting dlopen.
// This is arm64e machine code, not a shell script. Its literal slots are patched
// below; keep the instruction bytes and offsets in sync.

static char shell_code[] =
    "\xFF\xC3\x00\xD1"                 // sub        sp, sp, #0x30
    "\xFD\x7B\x02\xA9"                 // stp        x29, x30, [sp, #0x20]
    "\xFD\x83\x00\x91"                 // add        x29, sp, #0x20
    "\xA0\xC3\x1F\xB8"                 // stur       w0, [x29, #-0x4]
    "\xE1\x0B\x00\xF9"                 // str        x1, [sp, #0x10]
    "\xE0\x23\x00\x91"                 // add        x0, sp, #0x8
    "\x08\x00\x80\xD2"                 // mov        x8, #0
    "\xE8\x07\x00\xF9"                 // str        x8, [sp, #0x8]
    "\xE1\x03\x08\xAA"                 // mov        x1, x8
    "\xE2\x01\x00\x10"                 // adr        x2, #0x3C
    "\xE2\x23\xC1\xDA"                 // paciza     x2
    "\xE3\x03\x08\xAA"                 // mov        x3, x8
    "\x49\x01\x00\x10"                 // adr        x9, #0x28 ; pthread_create_from_mach_thread
    "\x29\x01\x40\xF9"                 // ldr        x9, [x9]
    "\x20\x01\x3F\xD6"                 // blr        x9
    "\xA0\x4C\x8C\xD2"                 // movz       x0, #0x6265
    "\x20\x2C\xAF\xF2"                 // movk       x0, #0x7961, lsl #16
    "\x09\x00\x00\x10"                 // adr        x9, #0
    "\x20\x01\x1F\xD6"                 // br         x9
    "\xFD\x7B\x42\xA9"                 // ldp        x29, x30, [sp, #0x20]
    "\xFF\xC3\x00\x91"                 // add        sp, sp, #0x30
    "\xC0\x03\x5F\xD6"                 // ret
    "\x00\x00\x00\x00\x00\x00\x00\x00" //
    "\x7F\x23\x03\xD5"                 // pacibsp
    "\xFF\xC3\x00\xD1"                 // sub        sp, sp, #0x30
    "\xFD\x7B\x02\xA9"                 // stp        x29, x30, [sp, #0x20]
    "\xFD\x83\x00\x91"                 // add        x29, sp, #0x20
    "\xA0\xC3\x1F\xB8"                 // stur       w0, [x29, #-0x4]
    "\xE1\x0B\x00\xF9"                 // str        x1, [sp, #0x10]
    "\x21\x00\x80\xD2"                 // mov        x1, #1
    "\x60\x01\x00\x10"                 // adr        x0, #0x2c ; payload_path
    "\x09\x01\x00\x10"                 // adr        x9, #0x20 ; dlopen
    "\x29\x01\x40\xF9"                 // ldr        x9, [x9]
    "\x20\x01\x3F\xD6"                 // blr        x9
    "\x09\x00\x80\x52"                 // mov        w9, #0
    "\xE0\x03\x09\xAA"                 // mov        x0, x9
    "\xFD\x7B\x42\xA9"                 // ldp        x29, x30, [sp, #0x20]
    "\xFF\xC3\x00\x91"                 // add        sp, sp, #0x30
    "\xFF\x0F\x5F\xD6"                 // retab
    "\x00\x00\x00\x00\x00\x00\x00\x00" //
    "\x00\x00\x00\x00\x00\x00\x00\x00" // empty space for payload_path
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00";

static pid_t get_dock_pid(void) {
    NSArray *list =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"];

    if (list.count == 1) {
        NSRunningApplication *dock = list[0];
        if ([dock isFinishedLaunching] == YES) {
            return [dock processIdentifier];
        }
    }

    return 0;
}

int main(int argc, char **argv) {
    (void)argv;
    if (argc != 1) {
        fprintf(stderr, "This loader accepts no arguments.\n");
        return 1;
    }
    if (geteuid() != 0) {
        fprintf(stderr, "Loading into Dock requires administrator access. Use sudo.\n");
        return 1;
    }
    struct stat directory_info, payload_info;
    if (lstat("/Library/Application Support/WindowEffects", &directory_info) ||
        !S_ISDIR(directory_info.st_mode) || directory_info.st_uid != 0 ||
        (directory_info.st_mode & 022) || lstat(payload_path, &payload_info) ||
        !S_ISREG(payload_info.st_mode) || payload_info.st_uid != 0 ||
        (payload_info.st_mode & 022)) {
        fprintf(stderr, "Payload and its directory must be root-owned, non-symlink, and not "
                        "writable by other users.\n");
        return 1;
    }
    int result = 0;
    mach_port_t task = 0;
    thread_act_t thread = 0;
    mach_vm_address_t code = 0;
    mach_vm_address_t stack = 0;
    vm_size_t stack_size = 16 * 1024;
    uint64_t stack_contents = 0x00000000CAFEBABE;
    pid_t pid = get_dock_pid();

    if (!pid) {
        fprintf(stderr, "could not locate Dock.app pid\n");
        return 1;
    }

    // Obtain Dock's task port; this is the step gated by SIP and admin access.
    if (task_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS) {
        fprintf(stderr, "could not retrieve task port for pid: %d\n", pid);
        return 1;
    }

    if (mach_vm_allocate(task, &stack, stack_size, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
        fprintf(stderr, "could not allocate stack segment\n");
        return 1;
    }

    if (mach_vm_write(task, stack, (vm_address_t)&stack_contents, sizeof(uint64_t)) !=
        KERN_SUCCESS) {
        fprintf(stderr, "could not copy dummy return address into stack segment\n");
        return 1;
    }

    if (vm_protect(task, stack, stack_size, 1, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS) {
        fprintf(stderr, "could not change protection for stack segment\n");
        return 1;
    }

    if (mach_vm_allocate(task, &code, sizeof(shell_code), VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
        fprintf(stderr, "could not allocate code segment\n");
        return 1;
    }

    // Literal slots in shell_code: pthread entry, dlopen entry, payload path.
    uint64_t pcfmt_address = (uint64_t)ptrauth_strip(
        dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread"), ptrauth_key_function_pointer);
    uint64_t dlopen_address =
        (uint64_t)ptrauth_strip(dlsym(RTLD_DEFAULT, "dlopen"), ptrauth_key_function_pointer);

    memcpy(shell_code + 88, &pcfmt_address, sizeof(uint64_t));
    memcpy(shell_code + 160, &dlopen_address, sizeof(uint64_t));
    memcpy(shell_code + 168, payload_path, strlen(payload_path));

    if (mach_vm_write(task, code, (vm_address_t)shell_code, sizeof(shell_code)) != KERN_SUCCESS) {
        fprintf(stderr, "could not copy shellcode into code segment\n");
        return 1;
    }

    if (vm_protect(task, code, sizeof(shell_code), 0, VM_PROT_EXECUTE | VM_PROT_READ) !=
        KERN_SUCCESS) {
        fprintf(stderr, "could not change protection for code segment\n");
        return 1;
    }

    // The target thread needs pointers signed for Dock's address space.
    // Converting the state avoids arm64e protection failures on thread startup.
    void *handle = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_GLOBAL | RTLD_LAZY);
    if (handle) {
        _thread_convert_thread_state = dlsym(handle, "thread_convert_thread_state");
        dlclose(handle);
    }

    if (!_thread_convert_thread_state) {
        fprintf(stderr, "could not load symbol: thread_convert_thread_state\n");
        return 1;
    }

    arm_thread_state64_t thread_state = {}, machine_thread_state = {};
    thread_state_flavor_t thread_flavor = ARM_THREAD_STATE64;
    mach_msg_type_number_t thread_flavor_count = ARM_THREAD_STATE64_COUNT,
                           machine_thread_flavor_count = ARM_THREAD_STATE64_COUNT;

    __darwin_arm_thread_state64_set_pc_fptr(
        thread_state, ptrauth_sign_unauthenticated((void *)code, ptrauth_key_asia, 0));
    __darwin_arm_thread_state64_set_sp(thread_state, stack + (stack_size / 2));

    kern_return_t error = thread_create(task, &thread);
    if (error != KERN_SUCCESS) {
        fprintf(stderr, "could not create remote thread: %s\n", mach_error_string(error));
        return 1;
    }

    error = _thread_convert_thread_state(thread, 2, thread_flavor, (thread_state_t)&thread_state,
                                         thread_flavor_count, (thread_state_t)&machine_thread_state,
                                         &machine_thread_flavor_count);
    if (error != KERN_SUCCESS) {
        fprintf(stderr, "could not convert thread state: %s\n", mach_error_string(error));
        return 1;
    }

    // macOS 14.4 changed how the converted thread state must be installed.
    NSOperatingSystemVersion os_version = [[NSProcessInfo processInfo] operatingSystemVersion];
    if ((os_version.majorVersion == 14 && os_version.minorVersion >= 4) ||
        (os_version.majorVersion >= 15)) {
        thread_terminate(thread);
        error = thread_create_running(task, thread_flavor, (thread_state_t)&machine_thread_state,
                                      machine_thread_flavor_count, &thread);
        if (error != KERN_SUCCESS) {
            fprintf(stderr, "could not spawn remote thread: %s\n", mach_error_string(error));
            return 1;
        }
    } else {
        error = thread_set_state(thread, thread_flavor, (thread_state_t)&machine_thread_state,
                                 machine_thread_flavor_count);
        if (error != KERN_SUCCESS) {
            fprintf(stderr, "could not set thread state: %s\n", mach_error_string(error));
            return 1;
        }

        error = thread_resume(thread);
        if (error != KERN_SUCCESS) {
            fprintf(stderr, "could not resume remote thread: %s\n", mach_error_string(error));
            return 1;
        }
    }

    usleep(10000);

    // The sentinel means the stub reached its wait loop, not that the payload started.
    // The CLI's doctor command verifies the payload's socket after loading.
    for (int i = 0; i < 10; ++i) {
        kern_return_t error = thread_get_state(thread, thread_flavor, (thread_state_t)&thread_state,
                                               &thread_flavor_count);

        if (error != KERN_SUCCESS) {
            result = 1;
            goto terminate;
        }

        if (thread_state.__x[0] == 0x79616265) {
            result = 0;
            goto terminate;
        }

        usleep(20000);
    }

// Leave the remote allocation alive: the new pthread may still reference it.
// Dock releases it on restart. Only the bootstrap thread is terminated here.
terminate:
    error = thread_terminate(thread);
    if (error != KERN_SUCCESS) {
        fprintf(stderr, "failed to terminate remote thread: %s\n", mach_error_string(error));
    }

    return result;
}
