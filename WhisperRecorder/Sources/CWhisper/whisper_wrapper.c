#include "include/whisper_wrapper.h"
#include <whisper.h>
#include <ggml.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

struct whisper_wrapper
{
    struct whisper_context *ctx;
    char *result_buffer;
};

whisper_wrapper_t *whisper_wrapper_create(const char *model_path)
{
    struct whisper_context_params params = whisper_context_default_params();

    whisper_wrapper_t *wrapper = (whisper_wrapper_t *)malloc(sizeof(whisper_wrapper_t));
    if (wrapper == NULL)
    {
        return NULL;
    }

    wrapper->ctx = whisper_init_from_file_with_params(model_path, params);
    wrapper->result_buffer = NULL;

    if (wrapper->ctx == NULL)
    {
        free(wrapper);
        return NULL;
    }

    return wrapper;
}

void whisper_wrapper_free(whisper_wrapper_t *wrapper)
{
    if (wrapper == NULL)
    {
        return;
    }

    if (wrapper->ctx != NULL)
    {
        whisper_free(wrapper->ctx);
    }

    if (wrapper->result_buffer != NULL)
    {
        free(wrapper->result_buffer);
    }

    free(wrapper);
}

bool whisper_wrapper_is_loaded(whisper_wrapper_t *wrapper)
{
    return wrapper != NULL && wrapper->ctx != NULL;
}

// Helper function to read WAV file content
// This is a simplified WAV loader - works with standard WAV files
bool read_wav_file(const char *filename, float **pcm, int *samples, int *sample_rate)
{
    FILE *fp = fopen(filename, "rb");
    if (!fp)
    {
        fprintf(stderr, "Failed to open WAV file: %s\n", filename);
        return false;
    }

    // Read WAV header
    char header[44];
    if (fread(header, 1, 44, fp) != 44)
    {
        fprintf(stderr, "Failed to read WAV header\n");
        fclose(fp);
        return false;
    }

    // Check if the file is a valid WAV file
    if (memcmp(header, "RIFF", 4) != 0 || memcmp(header + 8, "WAVE", 4) != 0)
    {
        fprintf(stderr, "Not a valid WAV file\n");
        fclose(fp);
        return false;
    }

    // Extract header info
    *sample_rate = *(int *)(header + 24);
    int num_channels = *(short *)(header + 22);
    int bits_per_sample = *(short *)(header + 34);
    int data_size = *(int *)(header + 40);

    // Debug info
    fprintf(stderr, "WAV file details:\n");
    fprintf(stderr, "  Sample rate: %d Hz\n", *sample_rate);
    fprintf(stderr, "  Channels: %d\n", num_channels);
    fprintf(stderr, "  Bits per sample: %d\n", bits_per_sample);
    fprintf(stderr, "  Data size: %d bytes\n", data_size);

    // Safety checks
    if (data_size <= 0)
    {
        fprintf(stderr, "Error: WAV data size is invalid: %d\n", data_size);
        fclose(fp);
        return false;
    }

    if (num_channels <= 0)
    {
        fprintf(stderr, "Error: Invalid number of channels: %d\n", num_channels);
        fclose(fp);
        return false;
    }

    if (bits_per_sample != 16 && bits_per_sample != 32 && bits_per_sample != 8 && bits_per_sample != 24)
    {
        fprintf(stderr, "Unsupported bits per sample: %d\n", bits_per_sample);
        fclose(fp);
        return false;
    }

    // Allocate memory for PCM data
    *samples = data_size / (bits_per_sample / 8) / num_channels;
    if (*samples <= 0)
    {
        fprintf(stderr, "Error: Invalid number of samples calculated: %d\n", *samples);
        fclose(fp);
        return false;
    }

    fprintf(stderr, "  Calculated samples: %d\n", *samples);

    *pcm = (float *)malloc(*samples * sizeof(float));
    if (!*pcm)
    {
        fprintf(stderr, "Failed to allocate memory for PCM data\n");
        fclose(fp);
        return false;
    }

    // Add support for more bit depths
    if (bits_per_sample == 16)
    {
        short *buf = (short *)malloc(data_size);
        if (!buf)
        {
            fprintf(stderr, "Failed to allocate memory for WAV data\n");
            free(*pcm);
            fclose(fp);
            return false;
        }

        if (fread(buf, 1, data_size, fp) != data_size)
        {
            fprintf(stderr, "Failed to read WAV data\n");
            free(buf);
            free(*pcm);
            fclose(fp);
            return false;
        }

        // Convert to float and handle multiple channels by averaging
        for (int i = 0; i < *samples; i++)
        {
            float sum = 0.0f;
            for (int j = 0; j < num_channels; j++)
            {
                sum += buf[i * num_channels + j] / 32768.0f;
            }
            (*pcm)[i] = sum / num_channels;
        }

        free(buf);
    }
    else if (bits_per_sample == 32)
    {
        float *buf = (float *)malloc(data_size);
        if (!buf)
        {
            fprintf(stderr, "Failed to allocate memory for WAV data\n");
            free(*pcm);
            fclose(fp);
            return false;
        }

        if (fread(buf, 1, data_size, fp) != data_size)
        {
            fprintf(stderr, "Failed to read WAV data\n");
            free(buf);
            free(*pcm);
            fclose(fp);
            return false;
        }

        // Handle multiple channels by averaging
        for (int i = 0; i < *samples; i++)
        {
            float sum = 0.0f;
            for (int j = 0; j < num_channels; j++)
            {
                sum += buf[i * num_channels + j];
            }
            (*pcm)[i] = sum / num_channels;
        }

        free(buf);
    }
    else if (bits_per_sample == 8)
    {
        // Handle 8-bit audio (uncommon but possible)
        unsigned char *buf = (unsigned char *)malloc(data_size);
        if (!buf)
        {
            fprintf(stderr, "Failed to allocate memory for WAV data\n");
            free(*pcm);
            fclose(fp);
            return false;
        }

        if (fread(buf, 1, data_size, fp) != data_size)
        {
            fprintf(stderr, "Failed to read WAV data\n");
            free(buf);
            free(*pcm);
            fclose(fp);
            return false;
        }

        // Convert to float and handle multiple channels by averaging
        for (int i = 0; i < *samples; i++)
        {
            float sum = 0.0f;
            for (int j = 0; j < num_channels; j++)
            {
                // 8-bit WAV is unsigned [0, 255], normalize to [-1.0, 1.0]
                sum += ((float)buf[i * num_channels + j] - 128.0f) / 128.0f;
            }
            (*pcm)[i] = sum / num_channels;
        }

        free(buf);
    }
    else if (bits_per_sample == 24)
    {
        // Handle 24-bit audio
        unsigned char *buf = (unsigned char *)malloc(data_size);
        if (!buf)
        {
            fprintf(stderr, "Failed to allocate memory for WAV data\n");
            free(*pcm);
            fclose(fp);
            return false;
        }

        if (fread(buf, 1, data_size, fp) != data_size)
        {
            fprintf(stderr, "Failed to read WAV data\n");
            free(buf);
            free(*pcm);
            fclose(fp);
            return false;
        }

        // Convert to float and handle multiple channels by averaging
        for (int i = 0; i < *samples; i++)
        {
            float sum = 0.0f;
            for (int j = 0; j < num_channels; j++)
            {
                // Convert 3 bytes to a 24-bit integer, then normalize
                int sample = (buf[3 * (i * num_channels + j)] << 8) |
                             (buf[3 * (i * num_channels + j) + 1] << 16) |
                             (buf[3 * (i * num_channels + j) + 2] << 24);
                sum += (float)sample / 2147483648.0f; // normalize to [-1.0, 1.0]
            }
            (*pcm)[i] = sum / num_channels;
        }

        free(buf);
    }

    fclose(fp);
    fprintf(stderr, "WAV file loaded successfully\n");
    return true;
}

// Common function to set up transcription parameters
void setup_params(struct whisper_full_params *params, bool use_language_detection)
{
    params->print_realtime = false;
    params->print_progress = false;
    params->print_timestamps = false;
    params->print_special = false;
    params->translate = false;
    params->language = use_language_detection ? "auto" : "en";
    params->n_threads = 4;
    params->offset_ms = 0;

    // Added for better handling of longer audio:
    params->max_len = 0;          // disable length constraints
    params->max_tokens = 0;       // disable token constraints
    params->duration_ms = 0;      // transcribe the full audio
    params->split_on_word = true; // try to split on word boundaries
}

const char *whisper_wrapper_transcribe_with_lang(whisper_wrapper_t *wrapper, const char *audio_path, bool use_language_detection)
{
    if (wrapper == NULL || wrapper->ctx == NULL || audio_path == NULL)
    {
        return "Error: Invalid parameters";
    }

    // Free any previous result
    if (wrapper->result_buffer != NULL)
    {
        free(wrapper->result_buffer);
        wrapper->result_buffer = NULL;
    }

    // Load audio file
    float *pcm = NULL;
    int n_samples = 0;
    int sample_rate = 0;

    if (!read_wav_file(audio_path, &pcm, &n_samples, &sample_rate))
    {
        wrapper->result_buffer = strdup("Error: Failed to load audio file");
        return wrapper->result_buffer;
    }

    // Resample to 16kHz if needed
    if (sample_rate != WHISPER_SAMPLE_RATE)
    {
        fprintf(stderr, "Warning: Audio sample rate (%d Hz) doesn't match Whisper's expected rate (%d Hz)\n",
                sample_rate, WHISPER_SAMPLE_RATE);
        // For a proper app, you'd implement resampling here
    }

    // Use whisper_full_params for transcription
    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

    // Set parameters for transcription
    setup_params(&params, use_language_detection);

    // Run the whisper inference
    if (whisper_full(wrapper->ctx, params, pcm, n_samples) != 0)
    {
        free(pcm);
        wrapper->result_buffer = strdup("Error: Failed to process audio with whisper");
        return wrapper->result_buffer;
    }

    free(pcm);

    // Get the transcription result
    int n_segments = whisper_full_n_segments(wrapper->ctx);
    if (n_segments <= 0)
    {
        wrapper->result_buffer = strdup("No speech detected");
        return wrapper->result_buffer;
    }

    // Allocate a buffer for the result (estimate size)
    int buffer_size = 1024 * 16; // 16KB initial buffer
    wrapper->result_buffer = (char *)malloc(buffer_size);
    if (!wrapper->result_buffer)
    {
        return "Error: Failed to allocate memory for transcription";
    }
    wrapper->result_buffer[0] = '\0'; // Empty string initially

    // Concatenate all segments
    for (int i = 0; i < n_segments; i++)
    {
        const char *segment_text = whisper_full_get_segment_text(wrapper->ctx, i);
        int current_length = strlen(wrapper->result_buffer);
        int segment_length = strlen(segment_text);

        // Check if we need to expand the buffer
        if (current_length + segment_length + 2 > buffer_size)
        {
            buffer_size *= 2;
            char *new_buffer = (char *)realloc(wrapper->result_buffer, buffer_size);
            if (!new_buffer)
            {
                free(wrapper->result_buffer);
                wrapper->result_buffer = strdup("Error: Failed to allocate memory for transcription");
                return wrapper->result_buffer;
            }
            wrapper->result_buffer = new_buffer;
        }

        // Append this segment
        strcat(wrapper->result_buffer, segment_text);

        // Add space between segments
        if (i < n_segments - 1)
        {
            strcat(wrapper->result_buffer, " ");
        }
    }

    return wrapper->result_buffer;
}

// Original transcribe function now calls the new one with auto language detection
const char *whisper_wrapper_transcribe(whisper_wrapper_t *wrapper, const char *audio_path)
{
    return whisper_wrapper_transcribe_with_lang(wrapper, audio_path, true);
}

const char *whisper_wrapper_transcribe_pcm_with_lang(whisper_wrapper_t *wrapper, const float *pcm_data, int n_samples, bool use_language_detection)
{
    if (wrapper == NULL || wrapper->ctx == NULL || pcm_data == NULL || n_samples <= 0)
    {
        return "Error: Invalid parameters";
    }

    // Free any previous result
    if (wrapper->result_buffer != NULL)
    {
        free(wrapper->result_buffer);
        wrapper->result_buffer = NULL;
    }

    // Use whisper_full_params for transcription
    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

    // Set parameters for transcription
    setup_params(&params, use_language_detection);
    params.no_context = true;
    params.single_segment = true;

    // Run the whisper inference directly on the provided PCM data
    if (whisper_full(wrapper->ctx, params, pcm_data, n_samples) != 0)
    {
        wrapper->result_buffer = strdup("Error: Failed to process audio with whisper");
        return wrapper->result_buffer;
    }

    // Get the transcription result
    int n_segments = whisper_full_n_segments(wrapper->ctx);
    if (n_segments <= 0)
    {
        wrapper->result_buffer = strdup("No speech detected");
        return wrapper->result_buffer;
    }

    // Allocate a buffer for the result (estimate size)
    int buffer_size = 1024 * 16; // 16KB initial buffer
    wrapper->result_buffer = (char *)malloc(buffer_size);
    if (!wrapper->result_buffer)
    {
        return "Error: Failed to allocate memory for transcription";
    }
    wrapper->result_buffer[0] = '\0'; // Empty string initially

    // Concatenate all segments
    for (int i = 0; i < n_segments; i++)
    {
        const char *segment_text = whisper_full_get_segment_text(wrapper->ctx, i);
        int current_length = strlen(wrapper->result_buffer);
        int segment_length = strlen(segment_text);

        // Check if we need to expand the buffer
        if (current_length + segment_length + 2 > buffer_size)
        {
            buffer_size *= 2;
            char *new_buffer = (char *)realloc(wrapper->result_buffer, buffer_size);
            if (!new_buffer)
            {
                free(wrapper->result_buffer);
                wrapper->result_buffer = strdup("Error: Failed to allocate memory for transcription");
                return wrapper->result_buffer;
            }
            wrapper->result_buffer = new_buffer;
        }

        // Append this segment
        strcat(wrapper->result_buffer, segment_text);

        // Add space between segments
        if (i < n_segments - 1)
        {
            strcat(wrapper->result_buffer, " ");
        }
    }

    return wrapper->result_buffer;
}

// Original PCM transcribe function now calls the new one with auto language detection
const char *whisper_wrapper_transcribe_pcm(whisper_wrapper_t *wrapper, const float *pcm_data, int n_samples)
{
    return whisper_wrapper_transcribe_pcm_with_lang(wrapper, pcm_data, n_samples, true);
}