#ifndef WHISPER_WRAPPER_H
#define WHISPER_WRAPPER_H

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

typedef struct whisper_wrapper whisper_wrapper_t;

#ifdef __cplusplus
extern "C"
{
#endif

    // Create a new whisper wrapper instance
    whisper_wrapper_t *whisper_wrapper_create(const char *model_path);

    // Free a whisper wrapper instance
    void whisper_wrapper_free(whisper_wrapper_t *wrapper);

    // Transcribe audio from a file
    const char *whisper_wrapper_transcribe(whisper_wrapper_t *wrapper, const char *audio_path);

    // Transcribe audio from a file with language detection option
    const char *whisper_wrapper_transcribe_with_lang(whisper_wrapper_t *wrapper, const char *audio_path, bool use_language_detection);

    // Transcribe audio from PCM data in memory (for streaming)
    const char *whisper_wrapper_transcribe_pcm(whisper_wrapper_t *wrapper, const float *pcm_data, int n_samples);

    // Transcribe audio from PCM data with language detection option
    const char *whisper_wrapper_transcribe_pcm_with_lang(whisper_wrapper_t *wrapper, const float *pcm_data, int n_samples, bool use_language_detection);

    // Check if the model is loaded
    bool whisper_wrapper_is_loaded(whisper_wrapper_t *wrapper);

#ifdef __cplusplus
}
#endif

#endif // WHISPER_WRAPPER_H