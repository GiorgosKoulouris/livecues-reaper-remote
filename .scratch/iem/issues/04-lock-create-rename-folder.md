# 04. Lock, create and rename mixes, the IEMs folder and its colour

Status: ready-for-agent
Blocked by: 03

## Build

- The page opens locked. One Unlock tap enables editing.
- Create with a name only. The first create makes the `IEMs` folder at the end of the track list. New mixes go inside it with master send off and the shared colour.
- Rename, refusing an empty or duplicate name. Duplicates already in the project are visible and can be renamed apart.
- Colour picker, stored in the project, recolouring the folder and all its mixes.
- **Move to end**, offered only when tracks sit after the folder.
- One undo step per operation.

## Done when

Specs cover first create versus later creates, name refusals, and a target GUID that has gone. `npm test` and `npm run check` pass.
