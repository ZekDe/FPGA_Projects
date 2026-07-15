/**
 * @file    button_gesture.c
 * @brief   Single / multi click and long-press detector for a single button.
 * @author  Emrah Duatepe
 */

#include "button_gesture.h"

void buttonGestureInit(button_gesture_t *obj,
                       uint32_t debounce_ms,
                       uint32_t long_press_ms,
                       uint32_t multi_click_window_ms,
                       uint32_t repeat_start_ms,
                       uint32_t repeat_end_ms,
                       uint32_t repeat_ramp_ms)
{
    obj->debounce_ms           = debounce_ms;
    obj->long_press_ms         = long_press_ms;
    obj->multi_click_window_ms = multi_click_window_ms;
    obj->repeat_start_ms       = repeat_start_ms;
    obj->repeat_end_ms         = repeat_end_ms;
    obj->repeat_ramp_ms        = repeat_ramp_ms;
}

button_event_t buttonGestureProcess(button_gesture_t *obj,
                                    uint8_t raw_pressed,
                                    uint32_t now,
                                    uint32_t *click_count_out)
{
    /* Simetrik debounce: 'stable', raw HEM basiste HEM birakista debounce_ms
       boyunca kararli olmadikca degismez. Boylece birakma/orta parazitleri de
       filtrelenir (eski TON on-delay idi: basisi debounce ediyor ama birakisi
       aninda geciriyordu). ton_debounce alanlari yeniden kullaniliyor:
       .aux = son gorulen raw seviyesi, .since = son seviye degisimi ani. */
    uint8_t stable;
    if (raw_pressed != obj->ton_debounce.aux)
    {
        obj->ton_debounce.aux   = raw_pressed;   // seviye degisti -> sayaci sifirla
        obj->ton_debounce.since = now;
    }
    if ((uint32_t)(now - obj->ton_debounce.since) >= obj->debounce_ms)
        stable = raw_pressed;                    // yeterince kararli -> kabul et
    else
        stable = obj->btn_stable;                // henuz kararli degil -> eski degeri koru

    uint8_t long_level = TON(&obj->ton_long,     stable,      now, obj->long_press_ms);
    uint8_t rise       = edgeDetection(&obj->ed_rise, stable);
    uint8_t long_edge  = edgeDetection(&obj->ed_long, long_level);

    obj->btn_stable = stable;

    // Tekrar-basis zorunlulugu: buton birakilana kadar olaylari yut.
    // Edge dedektorleri yukarida guncellendi (bayat edge patlamasin diye),
    // burada sadece olay uretimini bastiriyoruz.
    if (obj->ignore_until_release)
    {
        if (!stable)
        {
            obj->ignore_until_release = 0;   // birakildi → tekrar basisa hazir
        }
        else
        {
            return BTN_EVT_NONE;             // hala basili → yut
        }
    }

    if (rise)
    {
        if (!obj->window_active)
        {
            obj->window_active = 1;
            obj->click_count   = 1;
            obj->window_start  = now;
            obj->long_fired    = 0;
        }
        else
        {
            obj->click_count++;
        }
    }

    if (long_edge)
    {
        obj->long_fired      = 1;
        obj->click_count     = 0;
        obj->window_active   = 0;
        obj->last_repeat     = now;
        obj->long_started_at = now;

        if (click_count_out != 0)
        {
            *click_count_out = 0;
        }
        return BTN_EVT_LONG;
    }

    // Long press devam ediyorsa, ivmelendirilmis periyotta BTN_EVT_LONG_REPEAT dondur
    if (obj->long_fired && stable && obj->repeat_start_ms > 0)
    {
        // Su anki periyodu hesapla: start_ms -> end_ms arasinda dogrusal interpolasyon
        uint32_t period;
        uint32_t elapsed = now - obj->long_started_at;

        if (obj->repeat_ramp_ms == 0 || elapsed >= obj->repeat_ramp_ms)
        {
            period = obj->repeat_end_ms;
        }
        else if (obj->repeat_start_ms >= obj->repeat_end_ms)
        {
            uint32_t delta = obj->repeat_start_ms - obj->repeat_end_ms;
            period = obj->repeat_start_ms - (delta * elapsed) / obj->repeat_ramp_ms;
        }
        else
        {
            // start < end (yavaslama) - nadir ama destekle
            uint32_t delta = obj->repeat_end_ms - obj->repeat_start_ms;
            period = obj->repeat_start_ms + (delta * elapsed) / obj->repeat_ramp_ms;
        }

        if ((now - obj->last_repeat) >= period)
        {
            obj->last_repeat = now;
            return BTN_EVT_LONG_REPEAT;
        }
    }

    // Buton birakildiginda long state'ini sifirla ve BIRAKIS olayini uret.
    // (long_edge'de window_active=0/click_count=0 yapildigi icin ayni tick'te
    //  multi-click/single blogu firmaz; guvenle donebiliriz.)
    if (obj->long_fired && !stable)
    {
        obj->long_fired = 0;
        return BTN_EVT_LONG_RELEASED;
    }

    if (obj->window_active
        && ((now - obj->window_start) >= obj->multi_click_window_ms)
        && (stable == 0))
    {
        button_event_t event = BTN_EVT_NONE;
        uint32_t       count = obj->click_count;

        if (!obj->long_fired)
        {
            if (count == 1)
            {
                event = BTN_EVT_SINGLE;
            }
            else if (count >= 2)
            {
                event = BTN_EVT_MULTI;
            }
        }

        obj->window_active = 0;
        obj->click_count   = 0;
        obj->long_fired    = 0;

        if (click_count_out != 0)
        {
            *click_count_out = count;
        }
        return event;
    }

    return BTN_EVT_NONE;
}

void buttonGestureRequireRepress(button_gesture_t *obj)
{
    obj->ignore_until_release = 1;
    obj->window_active        = 0;
    obj->click_count          = 0;
    obj->long_fired           = 0;
}

void buttonGestureReset(button_gesture_t *obj)
{
    // Timing konfigurasyonunu koru, tum runtime state'i sifirla.
    // Uyku sonrasi kullanilir: buton birakisi uyku/spin-wait icinde gozlemlenmedigi
    // icin nesne "hala basili / long tetiklendi" state'inde kalir; sifirlamazsak
    // uyandiran basis taze bir rising edge uretmez ve hicbir olay firar.
    obj->ton_debounce.since   = 0;
    obj->ton_debounce.aux     = 0;
    obj->ton_long.since       = 0;
    obj->ton_long.aux         = 0;
    obj->ed_rise.aux          = 0;
    obj->ed_long.aux          = 0;
    obj->btn_stable           = 0;
    obj->click_count          = 0;
    obj->window_start         = 0;
    obj->window_active        = 0;
    obj->long_fired           = 0;
    obj->last_repeat          = 0;
    obj->long_started_at      = 0;
    obj->ignore_until_release = 0;
}
