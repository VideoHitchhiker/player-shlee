//
//  AppDelegate.m
//  hitchhiker
//
//  Created by shlee on 2018. 7. 24..
//  Copyright © 2018년 shlee. All rights reserved.
//

#import "AppDelegate.h"


#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libswscale/swscale.h>

#import <SDL.h>
#import <SDL_thread.h>

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    openPanel.prompt = @"Select";
    [openPanel beginWithCompletionHandler:^(NSInteger result){
        [self play:openPanel.URL];
    }];
}

- (void)play:(NSURL*)url {
    const char* path = url.absoluteString.UTF8String;
    
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) {
        NSLog(@"Could not initialize SDL - %s\n", SDL_GetError());
        return;
    }
    
    AVFormatContext *format = NULL;
    if (avformat_open_input(&format, path, NULL, NULL) != 0) {
        NSLog(@"Could not open file");
        return;
    }
    
    // Retrieve stream information
    if (avformat_find_stream_info(format, NULL) < 0) {
        NSLog(@"Could not find stream information");
        return; // Couldn't find stream information
    }
    
    // Dump information about file onto standard error
    av_dump_format(format, 0, path, 0);
    
    // Find the first video stream
    int videoStream = -1;
    for (int i = 0; i < format->nb_streams; i++)
        if (format->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStream = i;
            break;
        }
    if (videoStream == -1) {
        NSLog(@"Not a video file");
        return;
    }
    
    // Get a pointer to the codec context for the video stream
    const AVCodecParameters* codecpar = format->streams[videoStream]->codecpar;
    // Find the decoder for the video stream
    const AVCodec* codec = avcodec_find_decoder(codecpar->codec_id);
    if (codec == NULL) {
        NSLog(@"Unsupported codec!\n");
        return; // Codec not found
    }
    
    // Copy context
    AVCodecContext* codecctx = avcodec_alloc_context3(codec);
    if (avcodec_parameters_to_context(codecctx, codecpar) != 0) {
        NSLog(@"Couldn't copy codec context");
        return; // Error copying codec context
    }
    
    // Open codec
    if (avcodec_open2(codecctx, codec, NULL) < 0) {
        NSLog(@"Could not open codec");
        return; // Could not open codec
    }
    
    // Make a screen to put our video
    int w = codecpar->width;
    int wh = codecpar->width * codecpar->height;
    int wh_4 = codecpar->width * codecctx->height / 4;
    int w_2 = codecpar->width / 2;
    unsigned char* Y = (unsigned char *) malloc(wh);
    unsigned char* U = (unsigned char *) malloc(wh_4);
    unsigned char* V = (unsigned char *) malloc(wh_4);
    
    SDL_Window* window = SDL_CreateWindow("FFmpeg",
                                          SDL_WINDOWPOS_UNDEFINED,
                                          SDL_WINDOWPOS_UNDEFINED,
                                          640, 480, 0);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, 0);
    SDL_Texture* texture = SDL_CreateTexture(renderer,
                                             SDL_PIXELFORMAT_YV12,
                                             SDL_TEXTUREACCESS_STREAMING,
                                             codecctx->width,
                                             codecctx->height
                                             );
    
    // initialize SWS context for software scaling
    struct SwsContext* sws_ctx = sws_getContext(codecctx->width,
                                                codecctx->height,
                                                codecctx->pix_fmt,
                                                codecctx->width,
                                                codecctx->height,
                                                AV_PIX_FMT_YUV420P,
                                                SWS_BILINEAR,
                                                NULL,
                                                NULL,
                                                NULL
                                                );
    
    
    // Read frames and save first five frames to disk
    AVPacket packet;
    // Allocate video frame
    AVFrame* frame = av_frame_alloc();
    
    while (av_read_frame(format, &packet) >= 0) {
        // Is this a packet from the video stream?
        if (packet.stream_index == videoStream) {
            // Decode video frame
            // Did we get a video frame?
            if (avcodec_send_packet(codecctx, &packet) == 0 && avcodec_receive_frame(codecctx, frame) == 0) {
                
                unsigned char* data[AV_NUM_DATA_POINTERS];
                int linesize[AV_NUM_DATA_POINTERS];
                
                data[0] = Y;
                data[1] = U;
                data[2] = V;
                
                linesize[0] = w;
                linesize[1] = w_2;
                linesize[2] = w_2;
                
                // Convert the image into YUV format that SDL uses
                sws_scale(sws_ctx, (uint8_t const *const *) frame->data,
                          frame->linesize, 0, codecctx->height,
                          data, linesize);
                
                SDL_UpdateYUVTexture(texture, NULL,
                                     Y, w,
                                     U, w_2,
                                     V, w_2);
                
                SDL_RenderClear(renderer);
                SDL_RenderCopy(renderer, texture, NULL, NULL);
                SDL_RenderPresent(renderer);
                
                av_packet_unref(&packet);
            }
        }
        
        // Free the packet that was allocated by av_read_frame
        av_packet_unref(&packet);
        SDL_Event event;
        SDL_PollEvent(&event);
        switch (event.type) {
            case SDL_QUIT:
                SDL_Quit();
                exit(0);
                break;
            default:
                break;
        }
    }
    
    // Free the YUV frame
    av_frame_free(&frame);
    
    // Close the codec
    avcodec_free_context(&codecctx);
    
    // Close the video file
    avformat_close_input(&format);
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
