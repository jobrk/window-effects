#include "skylight.h"

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        uint32_t wid = (uint32_t)strtoul(argv[1], NULL, 10);
        WEAPI api = {0};
        if (!weLoad(&api)) return 2;
        float before = 0, after = 0;
        uint64_t tags = 0, afterTags = 0;
        CGError a = api.getAlpha(api.connection(), wid, &before);
        CGError t = api.getTags(api.connection(), wid, &tags, 64);
        if (a || t) { fprintf(stderr, "read failed: %d %d\n", a, t); return 1; }
        bool shadow = !(tags & (UINT64_C(1) << 3));
        CGError sa = api.setAlpha(api.connection(), wid, 0.63f);
        CGError st = weShadow(api, wid, !shadow);
        api.getAlpha(api.connection(), wid, &after);
        api.getTags(api.connection(), wid, &afterTags, 64);
        bool changedA = fabsf(after - 0.63f) < 0.01f;
        bool changedT = ((tags ^ afterTags) & (UINT64_C(1) << 3)) != 0;
        printf("alpha: before=%g after=%g status=%d verified=%d\n", before, after, sa, changedA);
        printf("shadow: before=%d after=%d status=%d verified=%d\n", shadow,
            !(afterTags & (UINT64_C(1) << 3)), st, changedT);
        if (changedA) api.setAlpha(api.connection(), wid, before);
        if (changedT) weShadow(api, wid, shadow);
        return changedA && changedT ? 0 : 1;
    }
}
