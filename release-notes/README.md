# Release notes

Before tagging `vX.Y.Z`, write `X.Y.Z.md` here in Markdown (headings and
`-` bullets). CI publishes it as the GitHub Release text, and the app shows
it on the update screen and once more after the update is installed.
Without a file, CI lists the commit subjects since the previous tag.

## How to write them

Write the notes the way you'd tell a friend at shul what changed in the
app. `test/release_notes_test.dart` checks new notes (after 0.7.0) for
the habits below, so `flutter test` fails on them before a release.

- **Say what changed, then stop.** One change per bullet, in one or two
  short sentences (40 words at most). If it needs more, the details belong
  on the website, not in the notes.
- **No slogans in bold.** Start the bullet with the change itself, not a
  bold title like "**A siddur that knows every line.**" Bold one word if
  people need to find it, like a setting's name.
- **Plain words.** Skip "seamless", "effortless", "robust", "intuitive",
  "experience", "elevate", "streamlined", "now really", "say goodbye to"
  and exclamation marks. Name the screen or setting instead.
- **Tell people where to find it.** "Settings → Customs", "the Torah tab".
- **Fixes say what was wrong.** "Morid HaTal showed in the summer for
  Ashkenaz outside Israel", not "Improved accuracy of seasonal additions".

Before and after, from 0.7.0:

> - **A siddur that knows every line.** Every line of the Ashkenaz, Sefard,
>   Edot HaMizrach, Chabad and Koren siddurim has been read and marked: what
>   is a prayer and what is an instruction, which days it is said, and which
>   lines are alternatives to each other. What Amud shows today now comes
>   from that, not from guessing at the formatting, so far fewer lines are
>   wrongly shown or left out.

> - Every line in all five siddurim is now marked with the days it's said,
>   so far fewer lines show up on the wrong day or go missing.

> - **Do Not Disturb while reading (Android).** Turn it on under Settings →
>   Reading & device, and Amud silences calls and notifications in the
>   siddur and restores them when you leave. It never overrides a Do Not
>   Disturb or Focus mode you already have on.

> - Android: Amud can turn on Do Not Disturb while you're in the siddur and
>   turn it off when you leave (Settings → Reading & device).
