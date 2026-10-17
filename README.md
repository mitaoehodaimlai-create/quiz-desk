# Quiz Desk

A proctored MCQ quiz platform for a class. Faculty upload a student list and a question bank, build timed quizzes, and see results live. Students sign in with their roll number and take the quiz in the browser.

It runs as a [claude.ai Artifact](https://claude.ai): a single HTML page with a shared database provided by the Artifact runtime. There is no server to host.

## Features

**Faculty**
- Upload the student list (Excel or CSV). Columns are matched by header: `Roll No`/`PRN`, `Name`, `Email`, `Division`.
- Upload a question bank: `Question, A, B, C, D, Answer, Topic, Difficulty, Marks`. Answer can be A–D, 1–4, or the option text. Students never see the answer key.
- Build a quiz by drawing N random questions filtered by topic and difficulty, set a time limit, assign it to divisions, and shuffle questions and options per student.
- Set a quiz live, close it, release results to students, or delete it.
- Results: live ranking, who is answering now, who hasn't started, accuracy per question, proctoring violations, and CSV export.

**Students**
- A countdown timer, an OMR-style answer sheet, and mark-for-review. Answers save automatically and survive reloads and dropped connections.
- After results are released: score, deductions and an answer review.

**Proctoring**
- Recorded as violations: switching tabs or windows, copy, cut, paste, right-click, dragging in content from other sites, leaving full screen, and pressing Print Screen.
- Faculty set the marks cut per violation, the number of free warnings, and auto-submit after N violations.
- A browser page cannot detect a second device or OS-level screenshots, so supervise exams that count.

## Groups: one link per group

Each group is a separate Artifact with its own link and its own database, so groups never share load. Each group is sized for 30 students.

```bash
python3 scripts/build_groups.py A B C
```

This writes `dist/quiz-group-a.html` and the other groups. Publish each file as its own Artifact, declaring these capabilities:

```json
{
  "db": { "rules": [
    { "path": "staff",       "read": "admin",    "write": "admin" },
    { "path": "pub",         "read": "view",     "write": "admin" },
    { "path": "quizzes",     "read": "view",     "write": "admin" },
    { "path": "subs",        "read": "admin",    "write": "admin" },
    { "path": "subs/{self}", "read": "interact", "write": "interact" }
  ] },
  "user": {},
  "downloads": true
}
```

Share each group's Artifact with only that group's students, at **Contributor** access. Viewers can't save answers.

## Data model

| Path | Who can read | Contents |
|---|---|---|
| `staff/roster` | Faculty | Student list |
| `staff/bank` | Faculty | Question bank with answers |
| `staff/key_<quizId>` | Faculty | Answer key for one quiz |
| `quizzes/<quizId>` | Everyone | Quiz questions without answers. The answer key is copied in only when results are released. |
| `pub/index` | Everyone | Small summary of non-draft quizzes. This is the only document students watch live. |
| `subs/<userId>` | That student and faculty | The student's attempts: answers, times and violations |

### Load for a full sitting
- Students watch one small summary document, download a quiz's questions once at Start, and read their own record once.
- Answers are kept on the device and synced every 15–20 seconds, with a random offset per student. Start, submit and leaving the tab sync immediately.
- Faculty watch student attempts only on the Quizzes and Results tabs, and the screen redraws at most every 2 seconds.

## Layout

```
src/quiz-desk.template.html   the page (group name is a placeholder)
dist/quiz-group-*.html        built group pages
scripts/build_groups.py       builds group pages from the template
samples/                      example student list and question bank (made-up data)
```

Keep real class lists and exported results out of this repository; `.gitignore` excludes `data/`, `results/` and `*-results.csv`.
