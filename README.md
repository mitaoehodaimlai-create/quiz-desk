# Quiz Desk

A proctored MCQ quiz platform for a class. Faculty upload a student list and a question bank, build timed quizzes, and see results live. Students sign in with their roll number and take the quiz in the browser.

It runs as a [claude.ai Artifact](https://claude.ai): a single HTML page with a shared database provided by the Artifact runtime. There is no server to host.

## Features

**Faculty**
- Upload the student list (Excel or CSV). Columns are matched by header: `Roll No`/`PRN`, `Name`, `Email`, `Division`.
- Upload a question bank: `Question, A, B, C, D, Answer, Topic, Difficulty, Marks`. Answer can be A–D, 1–4, or the option text. Students never see the answer key.
- Build a quiz by drawing N random questions filtered by topic and difficulty, set a time limit, assign it to divisions, and shuffle questions and options per student.
- Set a quiz live, close it, release results to students, or delete it.
- Questions are shown in full everywhere (bank, quiz, review, question accuracy), keeping line breaks for code and multi-line questions.
- Results: live ranking, who is answering now, who hasn't started, accuracy per question, tab switches with time away, proctoring violations, and CSV export.
- **Save all results (Excel)** on the Results and Learners tabs: one workbook per group with Summary, one results sheet per quiz, Question analysis (full statements, correct answers, % correct), Learner levels, Topic by level, Violations, Students and Activity.
- Learner analytics: slow, average and advanced learners, from one quiz or averaged across all quizzes. The thresholds are adjustable (defaults: slow below 40%, advanced from 75%). Each student's weakest and strongest topic, topic accuracy for each level, students not yet assessed, a suggested action for each level, and a CSV export. Levels use marks before proctoring deductions.

**Students**
- A countdown timer, an OMR-style answer sheet, and mark-for-review. Answers save automatically and survive reloads and dropped connections.
- After results are released: score, deductions and an answer review.

**Proctoring**
- Recorded as violations: switching tabs or windows, copy, cut, paste, right-click, dragging in content from other sites, leaving full screen, and pressing Print Screen.
- Faculty set the marks cut per violation, the number of free warnings, and auto-submit after N violations.
- A browser page cannot detect a second device or OS-level screenshots, so supervise exams that count.

**Faculty accounts**
- Each faculty member logs in with their own username and password to start the quiz platform. Until they do, nothing on the faculty side is shown: no uploads, quizzes, results or analytics.
- The first person to open a group creates the administrator account. The administrator adds faculty or other administrators, resets passwords, and disables or removes accounts. Faculty can change their own password under **My account**.
- A login lasts 8 hours in that browser tab. **Log out** ends it, and resetting, disabling or removing an account ends that person's sessions.
- After 5 wrong attempts there is a wait that doubles with each further mistake. If the administrator is locked out, the artifact's owner can reset all accounts; students, questions, quizzes, results and the activity log are kept.
- **Activity** tab: every login, upload, quiz creation, start, close, result release, deletion, export and account change, with the faculty member's name and time. Quiz cards show who created, started and closed each quiz.
- Only salted PBKDF2-SHA-256 hashes are stored, in `staff/faculty`, which only editors can read. No password is in this repository.
- Accounts sit on top of claude.ai access, so each faculty member also needs Editor access to the group's page. What students can read or write is enforced by the database rules below.

## Groups: one link per group

Each group is a separate Artifact with its own link and its own database, so groups never share load. Each group is sized for 30 students.

Put each group's claude.ai link in a local `groups.json` (it is git-ignored, so the links never reach this public repository):

```json
{ "A": "https://claude.ai/artifact/...", "B": "https://claude.ai/artifact/...", "C": "https://claude.ai/artifact/..." }
```

```bash
python3 scripts/build_groups.py A B C
```

This writes `dist/quiz-group-a.html` and the other groups (also git-ignored, since they contain the links). Publish each file as its own Artifact, declaring these capabilities:

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

**Two links per group.** Faculty use the group's link as it is. Students get the **student link**, which is the same address followed by `#student`. It always opens the student quiz screen, never the faculty login, and its answers go into that group's results. Logged-in faculty can copy it from the card at the top of the **Quizzes** tab.

## Data model

| Path | Who can read | Contents |
|---|---|---|
| `staff/faculty` | Faculty | Faculty accounts: name, username, role, status, password hash and salt |
| `staff/log/entries/<id>` | Faculty | Activity log: time, faculty member, action, details |
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

## Vercel + Supabase version (9 links)

`docs/app.html` is a standalone version that runs on Vercel with a Supabase database. No claude.ai account is needed.

| Link | Who | What |
|---|---|---|
| `/s/A`, `/s/B`, `/s/C` | Students | Roll number + PIN sign-in, then the quiz |
| `/f/A`, `/f/B`, `/f/C` | Faculty | Students and PINs, shared question bank, quizzes, results, learners, activity |
| `/r/A`, `/r/B`, `/r/C` | Faculty | Results and learner analytics only |

- **Faculty** sign in with email and password through Supabase Auth. The first person becomes the administrator; later sign-ups wait for approval under **Accounts**.
- **Students** never get a Supabase account. They sign in with roll number + PIN through `student_*` database functions that return a 12-hour session token. Five wrong PINs lock that roll number for 2 minutes.
- **Answer keys stay on the server.** Questions are sent to students without answers. Answers sent after the deadline (plus 20 seconds) are refused and the attempt is submitted; closing a quiz submits everyone still answering.
- **PINs** are stored as bcrypt hashes and shown to faculty once, with an Excel export of the PIN slips.
- **Shared question bank**; quizzes, students and results are per group.
- Tested locally with 80 students in one group signing in, starting, saving 3 times and submitting at the same moment: 0 errors, median 0.3 s per sign-in and 0.07 s per save.

### Setting up
1. Create a Supabase project. Run `supabase/migrations/20261020000000_quiz_desk.sql` in its SQL editor, or use `npx supabase link` and `npx supabase db push`.
2. In Supabase **Authentication → URL configuration**, set the Site URL to `https://quiz-desk.vercel.app` and add `https://quiz-desk.vercel.app/f/*` and `https://quiz-desk.vercel.app/r/*` as redirect URLs.
3. Put the Project URL and anon public key in `docs/config.js`, then deploy to Vercel. `vercel.json` routes `/s/:group`, `/f/:group` and `/r/:group` to `app.html`.
4. Open `/f/A` and create the first account; it becomes the administrator.
5. Supabase's built-in email sender allows only a few emails per hour, which limits sign-up confirmation and password-reset emails. For real use, add your own SMTP server under **Authentication → Emails**, or turn off email confirmation.

### Testing locally
`npx supabase start` (needs Docker) runs the database on this computer. Put `http://127.0.0.1:54321` and the local anon key in `docs/config.js` (don't commit them), serve `docs/`, and open `app.html#/f/A` or `app.html#/s/A`.

## Layout

```
src/quiz-desk.template.html   the claude.ai version of the page (group name is a placeholder)
docs/app.html, docs/app.css   the Vercel + Supabase version (9 links)
supabase/                     database schema, security rules and student functions
dist/quiz-group-*.html        built group pages
scripts/build_groups.py       builds group pages from the template
samples/                      example student list and question bank (made-up data)
```

A step-by-step user guide is at https://quiz-desk.vercel.app/guide (also on GitHub Pages: https://mitaoehodaimlai-create.github.io/quiz-desk/guide.html).

The website (`docs/`) is deployed on Vercel at https://quiz-desk.vercel.app using `vercel.json`. Like GitHub Pages, the demo there runs in preview mode; real quizzes run on each group's claude.ai page.

Keep real class lists and exported results out of this repository; `.gitignore` excludes `data/`, `results/` and `*-results.csv`.
