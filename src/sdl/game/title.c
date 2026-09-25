#include "game/title.h"

#include "generated/title_data.h"

/* Colodore, the same RGB as assets/png/force_title_c64.png. */
static const uint32_t title_rgb[16] = {
    0xFF000000u,
    0xFFFFFFFFu,
    0xFF813338u,
    0xFF75CEC8u,
    0xFF8E3C97u,
    0xFF56AC4Du,
    0xFF2E2C9Bu,
    0xFFEDF171u,
    0xFF8E5029u,
    0xFF553800u,
    0xFFC46C71u,
    0xFF4A4A4Au,
    0xFF7B7B7Bu,
    0xFFA9FF9Fu,
    0xFF706DEBu,
    0xFFB2B2B2u
};

static void blit_title(uint32_t *pixels)
{
    int cy, cx, py, px;

    for (cy = 0; cy < 25; ++cy) {
        for (cx = 0; cx < 40; ++cx) {
            const int cell = cy * 40 + cx;
            const uint8_t screen = force_title_screen[cell];
            const uint8_t colour = (uint8_t)(force_title_colour[cell] & 0x0Fu);
            const uint8_t slot[4] = {
                0,
                (uint8_t)(screen >> 4),
                (uint8_t)(screen & 0x0Fu),
                colour
            };

            for (py = 0; py < 8; ++py) {
                const uint8_t bits = force_title_bitmap[cell * 8 + py];
                uint32_t *dst = pixels + (cy * 8 + py) * FORCE_FB_W + cx * 8;

                for (px = 0; px < 4; ++px) {
                    const uint32_t rgb = title_rgb[slot[(bits >> (6 - 2 * px)) & 3]];
                    dst[px * 2] = rgb;
                    dst[px * 2 + 1] = rgb;
                }
            }
        }
    }
}

bool force_title_show(force_host *host, uint32_t *pixels)
{
    blit_title(pixels);
    return force_host_wait_key(host, pixels);
}
