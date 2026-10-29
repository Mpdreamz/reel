# Drives the fixture app (mise run live builds it and checks the take): a ticking counter, a Play button that
# starts a quiet 440 Hz tone, a text field and a list.
Launch ../build/ReelFixture.app

Output ../build/fixture.mp4
Output ../build/fixture.gif
Set Size 640x480
Set TypingSpeed 30ms
Set Voice system
Set Ducking 20%
Set Subtitles on
Set ZoomEasing smooth
Intro@slide-up,ease-out,700ms "reel" "the fixture, driven by a tape" 2.5s
Outro@wipe-left,600ms "That's reel" "mise run live"
Set OutroBackground #1d2b3a

Hide
Wait "Play"
Sleep 1s
Show
Caption "reel drives the fixture"
Say "This is the reel fixture."
Say@over "Now click [play] Play, and a tone starts."
Wait [play]
Caption "Click Play and the tone starts"
Zoom@ease-out,600ms cursor 2x
Click "Play"
Sleep 1s
Zoom off
Say "The tone keeps playing under the voice."
Sleep 1s
Caption "Type, select all, type again"
Speed 3x
Click #name
Type "hello reel"
Key cmd+a
Type "Musicbox"
Key return
Speed off
Caption off
Zoom #list 2x
Scroll down 10 #list
Sleep 1s
Zoom@snap off
Sleep 1s
