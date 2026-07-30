package com.valery.spotify_clone.spotify_clone

import com.ryanheise.audioservice.AudioServiceActivity

// Extends AudioServiceActivity (not FlutterActivity) so this activity and
// audio_service's foreground service share a single FlutterEngine. Without it
// the service would spin up a second engine -- a second PlayerBloc, a second
// audio pipeline -- and the notification would drive a player the UI can't see.
class MainActivity : AudioServiceActivity()
