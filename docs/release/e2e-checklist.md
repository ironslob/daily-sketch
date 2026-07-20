# End-to-End Checklist — Phase 13

Verify on staging/TestFlight or local stack with mock auth where noted.

| # | Step | Automated |
| --- | --- | --- |
| 1 | Guest opens app | UITest launch |
| 2 | Views Prompt and feed | UITest + API |
| 3 | Starts timed session | Manual / device |
| 4 | Backgrounds/reopens | Manual / device |
| 5 | Captures image | Manual / device |
| 6 | Reviews image | Manual / device |
| 7 | Reaches Save Your Creativity | Manual / device |
| 8 | Creates account | Manual / device |
| 9 | Completes profile | Manual / device |
| 10 | Publishes | API integration test |
| 11 | Sees Home completion state | Manual / device |
| 12 | Creates second Submission | API integration test |
| 13 | Likes another Submission | API integration test |
| 14 | Posts/deletes Reflection | API integration test |
| 15 | Browses profile | UITest + API |
| 16 | Shares | Manual / device |
| 17 | Reports and blocks | API integration test |
| 18 | Receives reminder | Manual / device |
| 19 | Deletes own Submission | API integration test |
| 20 | Deletes account | API integration test |

## Owner-run (physical device)

Steps 3–9, 11–12, 16, 18 require camera, notifications, or share sheet on a physical device. Record results in `physical-device-matrix.md`.
