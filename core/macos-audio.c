// CoreAudio output selection without changing macOS's default device.
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

static void check(OSStatus result, const char *action) {
    if (result != noErr) { fprintf(stderr, "%s failed (CoreAudio %d)\n", action, (int)result); exit(1); }
}
static AudioObjectPropertyAddress address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress value = {selector, scope, kAudioObjectPropertyElementMain};
    return value;
}
static char *string_property(AudioDeviceID id, AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress addr = address(selector, kAudioObjectPropertyScopeGlobal);
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    check(AudioObjectGetPropertyData(id, &addr, 0, NULL, &size, &value), "Read device label");
    if (!value) { fprintf(stderr, "Missing device label\n"); exit(1); }
    CFIndex capacity = CFStringGetMaximumSizeForEncoding(CFStringGetLength(value), kCFStringEncodingUTF8) + 1;
    char *text = calloc((size_t)capacity, 1);
    if (!text || !CFStringGetCString(value, text, capacity, kCFStringEncodingUTF8)) { fprintf(stderr, "Cannot read device label\n"); exit(1); }
    CFRelease(value);
    return text;
}
static int is_output(AudioDeviceID id) {
    AudioObjectPropertyAddress addr = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(id, &addr, 0, NULL, &size) != noErr || size < sizeof(UInt32)) return 0;
    AudioBufferList *buffers = malloc(size);
    if (!buffers) { fprintf(stderr, "Out of memory\n"); exit(1); }
    check(AudioObjectGetPropertyData(id, &addr, 0, NULL, &size, buffers), "Read output channels");
    UInt32 channels = 0;
    for (UInt32 i=0; i<buffers->mNumberBuffers; i++) channels += buffers->mBuffers[i].mNumberChannels;
    free(buffers);
    return channels > 0;
}
static void json_string(const char *text) {
    putchar('"');
    for (const unsigned char *p=(const unsigned char *)text; *p; p++) {
        if (*p=='"' || *p=='\\') { putchar('\\'); putchar(*p); }
        else if (*p < 32) printf("\\u%04x", *p);
        else putchar(*p);
    }
    putchar('"');
}
static AudioDeviceID *devices(UInt32 *count) {
    AudioObjectPropertyAddress addr = address(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    check(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, NULL, &size), "List audio devices");
    AudioDeviceID *result = malloc(size ? size : 1);
    if (!result) { fprintf(stderr, "Out of memory\n"); exit(1); }
    check(AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, result), "List audio devices");
    *count = size / sizeof(AudioDeviceID);
    return result;
}
static void consumed(void *user, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    (void)queue; (void)buffer;
    *(int *)user = 1;
}
static UInt32 u32(const unsigned char *p) {
    return (UInt32)p[0] | ((UInt32)p[1]<<8) | ((UInt32)p[2]<<16) | ((UInt32)p[3]<<24);
}
static unsigned u16(const unsigned char *p) { return p[0] | ((unsigned)p[1]<<8); }
static void play(const char *uid, const char *path) {
    UInt32 count; AudioDeviceID *all = devices(&count);
    int found = 0;
    for (UInt32 i=0; i<count; i++) {
        if (!is_output(all[i])) continue;
        char *id = string_property(all[i], kAudioDevicePropertyDeviceUID);
        if (strcmp(id, uid)==0) found=1;
        free(id);
    }
    free(all);
    if (!found) { fprintf(stderr, "Selected macOS audio device is unavailable: %s\n", uid); exit(1); }
    FILE *file = fopen(path, "rb");
    if (!file) { perror(path); exit(1); }
    unsigned char header[44];
    if (fread(header,1,44,file)!=44 || memcmp(header,"RIFF",4) || memcmp(header+8,"WAVEfmt ",8) ||
        u32(header+16)!=16 || u16(header+20)!=1 || u16(header+22)!=1 || u32(header+24)!=22050 ||
        u16(header+34)!=16 || memcmp(header+36,"data",4)) {
        fprintf(stderr,"Invalid RobotSpeak PCM file\n"); exit(1);
    }
    UInt32 bytes = u32(header+40);
    if (!bytes || bytes%2 || bytes>16*1024*1024) { fprintf(stderr,"Invalid PCM length\n"); exit(1); }
    AudioStreamBasicDescription format = {0};
    format.mSampleRate=22050; format.mFormatID=kAudioFormatLinearPCM;
    format.mFormatFlags=kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket=2; format.mFramesPerPacket=1; format.mBytesPerFrame=2;
    format.mChannelsPerFrame=1; format.mBitsPerChannel=16;
    int completed=0;
    AudioQueueRef queue;
    check(AudioQueueNewOutput(&format, consumed, &completed, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &queue), "Create audio queue");
    CFStringRef target=CFStringCreateWithCString(NULL,uid,kCFStringEncodingUTF8);
    if (!target) { fprintf(stderr,"Invalid device UID\n"); exit(1); }
    check(AudioQueueSetProperty(queue,kAudioQueueProperty_CurrentDevice,&target,sizeof(target)), "Select audio device");
    CFRelease(target);
    AudioQueueBufferRef buffer;
    check(AudioQueueAllocateBuffer(queue,bytes,&buffer), "Allocate audio buffer");
    if (fread(buffer->mAudioData,1,bytes,file)!=bytes || fgetc(file)!=EOF) { fprintf(stderr,"Invalid PCM length\n"); exit(1); }
    fclose(file);
    buffer->mAudioDataByteSize=bytes;
    check(AudioQueueEnqueueBuffer(queue,buffer,0,NULL), "Queue audio");
    check(AudioQueueStart(queue,NULL), "Play audio");
    CFAbsoluteTime deadline=CFAbsoluteTimeGetCurrent()+bytes/44100.0+5;
    while (!completed && CFAbsoluteTimeGetCurrent()<deadline) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.05,true);
    if (!completed) { AudioQueueDispose(queue,true); fprintf(stderr,"Audio playback timed out\n"); exit(1); }
    check(AudioQueueStop(queue,false), "Drain audio");
    UInt32 running=1;
    while (running && CFAbsoluteTimeGetCurrent()<deadline) {
        UInt32 size=sizeof(running);
        check(AudioQueueGetProperty(queue,kAudioQueueProperty_IsRunning,&running,&size), "Wait for audio");
        if (running) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.05,true);
    }
    check(AudioQueueDispose(queue,true), "Close audio queue");
    if (running) { fprintf(stderr,"Audio drain timed out\n"); exit(1); }
}
int main(int argc, char **argv) {
    if (argc==2 && strcmp(argv[1],"list")==0) {
        UInt32 count; AudioDeviceID *all=devices(&count); int first=1;
        putchar('[');
        for (UInt32 i=0;i<count;i++) {
            if (!is_output(all[i])) continue;
            char *uid=string_property(all[i],kAudioDevicePropertyDeviceUID);
            char *name=string_property(all[i],kAudioObjectPropertyName);
            if (!first) putchar(',');
            first=0;
            printf("{\"id\":"); json_string(uid); printf(",\"name\":"); json_string(name); putchar('}');
            free(uid); free(name);
        }
        free(all); puts("]"); return 0;
    }
    if (argc==4 && strcmp(argv[1],"play")==0) { play(argv[2],argv[3]); return 0; }
    fprintf(stderr,"Usage: macos-audio list | play <UID> <WAV>\n"); return 1;
}
