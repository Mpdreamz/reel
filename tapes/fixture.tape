# Drives the fixture app (mise run live builds it and checks the take): a ticking counter, a Play button that
# starts a quiet 440 Hz tone, a text field and a list.
Output ../build/fixture.mp4
Set Size 640x480
Set TypingSpeed 30ms

Launch ../build/ReelFixture.app

Wait "Play"
Sleep 500ms
Click "Play"
Sleep 1s
Click #name
Type "hello reel"
Key cmd+a
Type "Musicbox"
Key return
Scroll down 10 #list
Sleep 1s
