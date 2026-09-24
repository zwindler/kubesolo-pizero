// VNC backend for doomgeneric: DOOM serves its own framebuffer over RFB,
// no X server, no SDL. The game is paused while no client is connected.

#include "doomkeys.h"
#include "doomgeneric.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <rfb/rfb.h>
#include <rfb/keysym.h>

#define KEYQUEUE_SIZE 64

static rfbScreenInfoPtr s_Screen;
static unsigned short s_KeyQueue[KEYQUEUE_SIZE];
static unsigned int s_KeyQueueWriteIndex;
static unsigned int s_KeyQueueReadIndex;
static uint64_t s_PausedMs;
static char *s_Passwords[2];

static uint64_t monotonic_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int convertToDoomKey(rfbKeySym key)
{
    switch (key)
    {
    case XK_Return:
    case XK_KP_Enter:    return KEY_ENTER;
    case XK_Escape:      return KEY_ESCAPE;
    case XK_Tab:         return KEY_TAB;
    case XK_BackSpace:   return KEY_BACKSPACE;
    case XK_Left:        return KEY_LEFTARROW;
    case XK_Right:       return KEY_RIGHTARROW;
    case XK_Up:          return KEY_UPARROW;
    case XK_Down:        return KEY_DOWNARROW;
    case XK_Control_L:
    case XK_Control_R:   return KEY_FIRE;
    case XK_space:       return KEY_USE;
    case XK_Shift_L:
    case XK_Shift_R:     return KEY_RSHIFT;
    case XK_Alt_L:
    case XK_Alt_R:
    case XK_Meta_L:
    case XK_Meta_R:      return KEY_RALT;
    case XK_F1:          return KEY_F1;
    case XK_F2:          return KEY_F2;
    case XK_F3:          return KEY_F3;
    case XK_F4:          return KEY_F4;
    case XK_F5:          return KEY_F5;
    case XK_F6:          return KEY_F6;
    case XK_F7:          return KEY_F7;
    case XK_F8:          return KEY_F8;
    case XK_F9:          return KEY_F9;
    case XK_F10:         return KEY_F10;
    case XK_F11:         return KEY_F11;
    case XK_F12:         return KEY_F12;
    case XK_minus:       return KEY_MINUS;
    case XK_equal:       return KEY_EQUALS;
    case XK_Pause:       return KEY_PAUSE;
    default:
        // Latin-1 keysyms map to their character; anything else is ignored.
        if (key < 0x100)
            return tolower((int)key);
        return -1;
    }
}

static void onKey(rfbBool down, rfbKeySym keySym, rfbClientPtr cl)
{
    (void)cl;
    int key = convertToDoomKey(keySym);
    if (key < 0)
        return;

    s_KeyQueue[s_KeyQueueWriteIndex] = (unsigned short)(((down ? 1 : 0) << 8) | (key & 0xFF));
    s_KeyQueueWriteIndex = (s_KeyQueueWriteIndex + 1) % KEYQUEUE_SIZE;
}

void DG_Init()
{
    s_Screen = rfbGetScreen(NULL, NULL, DOOMGENERIC_RESX, DOOMGENERIC_RESY, 8, 3, 4);
    if (!s_Screen)
    {
        fprintf(stderr, "rfbGetScreen failed\n");
        exit(1);
    }

    // doomgeneric writes 0x00RRGGBB words, i.e. B,G,R,X in memory.
    s_Screen->serverFormat.redShift = 16;
    s_Screen->serverFormat.greenShift = 8;
    s_Screen->serverFormat.blueShift = 0;

    s_Screen->desktopName = "DOOM";
    s_Screen->frameBuffer = (char *)DG_ScreenBuffer;
    s_Screen->alwaysShared = TRUE;
    s_Screen->kbdAddEvent = onKey;

    const char *port = getenv("VNC_PORT");
    s_Screen->port = port ? atoi(port) : 5900;
    s_Screen->ipv6port = s_Screen->port;

    const char *password = getenv("VNC_PASSWORD");
    if (password && *password)
    {
        s_Passwords[0] = strdup(password);
        s_Passwords[1] = NULL;
        s_Screen->authPasswdData = (void *)s_Passwords;
        s_Screen->passwordCheck = rfbCheckPasswordByList;
    }

    rfbInitServer(s_Screen);
    printf("DG_Init: VNC server listening on port %d (%dx%d)\n", s_Screen->port, DOOMGENERIC_RESX, DOOMGENERIC_RESY);
}

void DG_DrawFrame()
{
    if (s_Screen->clientHead)
        rfbMarkRectAsModified(s_Screen, 0, 0, DOOMGENERIC_RESX, DOOMGENERIC_RESY);
}

void DG_SleepMs(uint32_t ms)
{
    // Serve the network while we wait instead of sleeping blindly.
    rfbProcessEvents(s_Screen, (long)ms * 1000);
}

uint32_t DG_GetTicksMs()
{
    // Time spent paused (no client) is hidden from the game so that it
    // resumes where it was instead of trying to catch up.
    return (uint32_t)(monotonic_ms() - s_PausedMs);
}

int DG_GetKey(int *pressed, unsigned char *doomKey)
{
    if (s_KeyQueueReadIndex == s_KeyQueueWriteIndex)
        return 0;

    unsigned short keyData = s_KeyQueue[s_KeyQueueReadIndex];
    s_KeyQueueReadIndex = (s_KeyQueueReadIndex + 1) % KEYQUEUE_SIZE;

    *pressed = keyData >> 8;
    *doomKey = keyData & 0xFF;
    return 1;
}

void DG_SetWindowTitle(const char *title)
{
    (void)title;
}

int main(int argc, char **argv)
{
    doomgeneric_Create(argc, argv);

    for (;;)
    {
        if (!s_Screen->clientHead)
        {
            uint64_t start = monotonic_ms();
            rfbProcessEvents(s_Screen, 500000);
            s_PausedMs += monotonic_ms() - start;
            continue;
        }

        rfbProcessEvents(s_Screen, 0);
        doomgeneric_Tick();
    }

    return 0;
}
