#ifndef REX_AUDIO_H
#define REX_AUDIO_H

#ifdef __cplusplus
extern "C" {
#endif

int rex_audio_platform_play(const char* path);
void rex_audio_platform_stop(void);

#ifdef __cplusplus
}
#endif

#endif
// not in this update for now iwll do it later 