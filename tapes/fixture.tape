# Drives the fixture app (mise run live builds it and checks the take): a ticking counter, a Play button that
# starts a quiet 440 Hz tone, a text field and a list.
Output ../build/fixture.mp4
Output ../build/fixture.gif
Set Size 640x480
Set TypingSpeed 30ms
Set Voice system
Set Ducking 20%
Set Subtitles on

Launch ../build/ReelFixture.app

Caption "reel drives the fixture"
Wait "Play"
Say "This is the reel fixture."
Say@over "Now click [play] Play, and a tone starts."
Wait [play]
Caption "Click Play and the tone starts"
Click "Play"
Sleep 1s
Say "The tone keeps playing under the voice."
Sleep 1s
Caption "Type, select all, type again"
Click #name
Type "hello reel"
Key cmd+a
Type "Musicbox"
Key return
Caption off
Scroll down 10 #list
Sleep 1s
