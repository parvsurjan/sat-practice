# SATPrep

A standalone iOS app for SAT Reading & Writing practice, built from the three
question PDFs in this repo. No network, no accounts — everything ships in the bundle
and all progress stays on the device.

**1,845 questions** (611 easy · 624 medium · 610 hard), each with answer choices,
the correct answer, the official rationale, difficulty, domain and skill.
**133 questions include a chart or table**, rendered from the PDFs as images.

## Deploying to your phone

1. Open `SATPrep/SATPrep.xcodeproj` in Xcode.
2. Select the **SATPrep** target → **Signing & Capabilities**.
   - Check **Automatically manage signing**.
   - Pick your Apple ID under **Team** (add one in Xcode → Settings → Accounts).
   - Change the **Bundle Identifier** if `com.parvsurjan.SATPrep` is taken —
     anything unique works, e.g. `com.yourname.SATPrep`.
3. Plug in your iPhone and select it as the run destination.
4. **Product → Scheme → Edit Scheme → Run → Build Configuration: Release**, then
   **Product → Run**.
5. First launch only: on the phone, go to **Settings → General → VPN & Device
   Management** and trust your developer certificate.

With a free Apple ID the app expires after 7 days — rebuild to renew it. A paid
Apple Developer account extends this to a year.

Minimum iOS 17. Builds clean against the iOS 27 SDK (Xcode 27).

## Look and feel

The answering experience deliberately mirrors the College Board **Bluebook** app so
practice here transfers to test day: outlined answer cards with circled letters, the
same blue selection state, green/red result states, **Mark for Review**, and the
**ABC** cross-out tool. The palette lives in `Theme.swift` — change it in one place.

The app is **light mode only** (`UIUserInterfaceStyle = Light`), like Bluebook, so
charts and tables lifted from the PDFs always sit on the white background they were
drawn for.

## The three screens

**Practice** — one question at a time, drawn from the whole bank with unseen
questions first. Difficulty, domain and skill are shown up front. Pick an answer
and the correct choice, your choice, and the full rationale appear immediately.
**Mark for Review** saves a question; the **ABC** button turns on Bluebook's
cross-out tool for eliminating choices; the filter icon narrows practice to
particular difficulties or categories; the shuffle icon skips. Tap a chart to enlarge it.

**Review** — two separate sections:
- *Needs work* — every question you have missed. The two dots on each row show
  progress toward retiring it.
- *Bookmarked* — everything you have bookmarked, independent of correctness.

A missed question leaves *Needs work* only after **two correct answers in a row**.
One correct answer is not enough, and missing it again puts it back and resets the
streak.

**Finishing the bank starts it over.** Once every question has been answered and
*Needs work* is empty, the app resets itself automatically and silently — progress,
stats and bookmarks all clear, and the next question is served as if the app were
new. Practice never runs out.

**Stats** — overall accuracy, questions answered, how much of the bank you have
covered, and accuracy broken down by difficulty, by category, and by skill.
The skill list is sorted weakest-first, so your soft spots are at the top.

## Layout

```
SATPrep/
  SATPrep.xcodeproj
  SATPrep/
    SATPrepApp.swift      app entry, three tabs, light-mode lock
    Theme.swift           Bluebook-style palette and metrics
    Models.swift          Question, QuestionProgress (review-queue rule), Cycle
    Store.swift           loads questions, persists progress, builds the queues
    QuestionView.swift    question card, choices, figures, result panel
    PracticeView.swift    Practice tab + filters
    ReviewView.swift      Review tab (needs work / bookmarked)
    StatsView.swift       Stats tab
    Resources/
      questions.json      all 1,845 questions
      figures/            133 chart and table images
```

Progress is written to JSON in Application Support, independent of the question
set, so updating the questions does not disturb it. Stats → **Reset all progress**
clears it deliberately, and finishing the whole bank clears it automatically.

## Regenerating the question data

`tools/extract.py` and `tools/build.py` parse the PDFs; `tools/crop.py` trims the
figure images. They need `pymupdf` and `pillow`:

```sh
python3 -m venv venv && ./venv/bin/pip install pymupdf pillow
./venv/bin/python tools/extract.py    # parses PDFs -> raw.json + figure PNGs
./venv/bin/python tools/crop.py       # trims figure whitespace
./venv/bin/python tools/build.py      # -> questions.json
```

Then copy `questions.json` and the cropped figures into `SATPrep/SATPrep/Resources/`.
