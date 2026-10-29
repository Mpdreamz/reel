# Drives tapes/web/fixture.html in a browser reel starts (mise run live-web records it and checks the take): a Play
# button that starts a quiet 440 Hz tone, a text field, a list and a link. The page writes what happened to its log,
# and the tape waits for each entry, so a step that did not work stops the take.
Output ../build/web.mp4
Output ../build/web.gif
Set Viewport 1000x700
Set ZoomEasing smooth

Open web/fixture.html

Wait "reel web fixture"
Caption "A web page, driven by a tape"
Click "Play"
Wait "played"
Sleep 1s
Caption "Type, select all, type again"
Click "Name"
Type "hello reel"
Key cmd+a
Type "Musicbox"
Key return
Wait "submitted Musicbox"
Caption off
Zoom #list 2x
Scroll down 8 #list
Wait "scrolled"
Sleep 500ms
Zoom off
Click "Next page"
Wait "Second page"
Sleep 1s
