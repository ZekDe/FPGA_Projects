#ifndef BUTTON_GESTURE_H
#define BUTTON_GESTURE_H

#include "stdint.h"
#include "ton.h"
#include "edge_detection.h"

#define CONTROLLER_PERIOD           1000//2500
#define DEADBAND_MM  				0.042f   /* 1 full-step */

#define BTN_DEBOUNCE_MS           50U
#define BTN_LONG_PRESS_MS         3000U
#define BTN_MULTI_CLICK_WINDOW_MS 600U
#define LEVEL_MAX                 2U

typedef enum
{
    BTN_EVT_NONE        = 0,
    BTN_EVT_SINGLE      = 1,
    BTN_EVT_MULTI       = 2,
    BTN_EVT_LONG        = 3,
    BTN_EVT_LONG_REPEAT = 4,
    BTN_EVT_LONG_RELEASED = 5   /* LONG (veya LONG_REPEAT) sonrasi buton BIRAKILINCA bir kez firlar */
} button_event_t;

typedef struct
{
    uint32_t debounce_ms;
    uint32_t long_press_ms;
    uint32_t multi_click_window_ms;
    uint32_t repeat_start_ms;     // basili tutarken ilk tekrarlama periyodu
    uint32_t repeat_end_ms;       // ivmelendirme sonu periyodu (en hizli)
    uint32_t repeat_ramp_ms;      // start'tan end'e dogrusal gecis suresi (0: ivme yok)

    ton_t ton_debounce;
    ton_t ton_long;
    edge_detection_t ed_rise;
    edge_detection_t ed_long;

    uint8_t  btn_stable;
    uint32_t click_count;
    uint32_t window_start;
    uint8_t  window_active;
    uint8_t  long_fired;
    uint32_t last_repeat;
    uint32_t long_started_at;     // LONG event'in tetiklendigi zaman (ramp basi)
    uint8_t  ignore_until_release; // 1: buton birakilana kadar olaylari yut
} button_gesture_t;

/**
 * @brief Configure timing parameters of a button-gesture instance.
 *        Assumes the struct is zero-initialised (e.g. static / global).
 */
/**
 * @brief Configure timing parameters of a button-gesture instance.
 *
 * @param repeat_start_ms  Long press tutarken ilk tekrarlama periyodu (ms).
 *                         0: tekrarlama kapali (sadece bir kez BTN_EVT_LONG firar).
 * @param repeat_end_ms    Ivmelendirme sonu en hizli periyot (ms).
 *                         repeat_start_ms ile esit verilirse ivmelendirme yok.
 * @param repeat_ramp_ms   start'tan end'e dogrusal gecis suresi (ms).
 *                         0: ivme yok, baslangictan itibaren repeat_start_ms kullanilir.
 */
void buttonGestureInit(button_gesture_t *obj,
                       uint32_t debounce_ms,
                       uint32_t long_press_ms,
                       uint32_t multi_click_window_ms,
                       uint32_t repeat_start_ms,
                       uint32_t repeat_end_ms,
                       uint32_t repeat_ramp_ms);

/**
 * @brief Feed the raw button level (1 = pressed) on every tick.
 * @param obj              gesture instance
 * @param raw_pressed      raw GPIO level, 1 = pressed
 * @param now              HAL_GetTick() value in ms
 * @param click_count_out  optional, filled with the click count that produced
 *                         the returned SINGLE/MULTI event (NULL to ignore)
 * @return event fired on this tick, or BTN_EVT_NONE
 *
 * A LONG event fires once at the long-press threshold; any pending click
 * window is cancelled so no spurious SINGLE fires on release.
 */
button_event_t buttonGestureProcess(button_gesture_t *obj,
                                    uint8_t raw_pressed,
                                    uint32_t now,
                                    uint32_t *click_count_out);

/**
 * @brief Mevcut basisi gecersiz kil; yeni olay icin buton birakilip tekrar
 *        basilmasini zorunlu kil.
 *
 * Timing konfigurasyonunu (debounce, long, multi-click, repeat) KORUR; yalniz
 * bekleyen click penceresini ve long durumunu temizler ve bir sonraki
 * birakmaya kadar tum olaylari yutar. Bir ekran uzun basisla kapanip baska bir
 * ekrana gecildiginde, ayni basili butonun yeni ekranda istem disi olay
 * uretmesini onler.
 */
void buttonGestureRequireRepress(button_gesture_t *obj);

/**
 * @brief Tum runtime state'i sifirla (timing konfigurasyonu korunur).
 *
 * Uyku sonrasi uyanista kullanilir: buton birakisi uyku/spin-wait icinde
 * gozlemlenmedigi icin nesne bayat "hala basili / long tetiklendi" state'inde
 * kalir. Sifirlanmazsa uyandiran basis taze bir rising/long edge uretmez ve
 * hicbir olay firar. Sifirlandiktan sonra basili buton temiz bir yeni basis
 * olarak algilanir.
 */
void buttonGestureReset(button_gesture_t *obj);

#endif /* BUTTON_GESTURE_H */
