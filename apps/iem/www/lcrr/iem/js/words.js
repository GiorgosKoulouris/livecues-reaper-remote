// IEM Setup: every sentence the page shows (pure). The bridge sends codes and fields; the wording is here, so a
// reply never carries prose and each sentence can be tested against recorded replies.
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else { var L = root.LCRR = root.LCRR || {}; (L.iem = L.iem || {}).words = api; }
})(this, function () {
  "use strict";

  var CHIP = { connecting: "Connecting…", ready: "Connected", offline: "REAPER unreachable", "bridge-down": "IEM Setup not running" };
  var BANNER = {
    offline: "Can’t reach REAPER. This page keeps retrying.",
    "bridge-down": "IEM Setup isn’t running in REAPER, so nothing can be changed. Open the Actions list and run “LCRR IEM: Bridge”."
  };

  var ERRORS = {
    bad_request: "REAPER’s bridge could not read that request.",
    request_truncated: "The request was cut off on the way to REAPER.",
    unknown_command: "This page asked for something the installed bridge does not know. Re-run install.ps1 and restart REAPER.",
    internal: "The bridge hit a problem with the project.",
    empty_name: "Give the mix a name.",
    duplicate_name: "Another mix already has that name. Monitor can’t open two mixes with one name.",
    not_a_stray: "That mix is already in the IEMs folder. The page has been refreshed.",
    track_gone: "That track is no longer in the project. The page has been refreshed; try again.",
    not_a_mix: "That track isn’t a mix any more. The page has been refreshed; try again.",
    not_the_folder: "That isn’t the IEMs folder any more. The page has been refreshed; try again.",
    nothing_to_move: "Nothing sits after the IEMs folder, so there is nothing to move.",
    multiple_outputs: "That mix has more than one hardware output, so it is read-only here. Change it in REAPER.",
    bad_channel: "That output channel is not on the audio device. The page has been refreshed; pick again.",
    no_device: "The audio device is closed, so its channels are not known. Open it in REAPER to pick an output.",
    not_a_source: "That track can’t feed a mix. The page has been refreshed; try again.",
    bad_colour: "That colour could not be used.",
    request_too_long: "The request is too long to send.",
    unreachable: "REAPER did not take the request.",
    no_reply: "The bridge did not answer."
  };

  function error(err) {
    var code = err && err.code;
    return ERRORS[code] || ("Something went wrong (" + (code || "unknown") + ").");
  }

  // Labels and hints for the editing controls.
  var UI = {
    newMix: "Mix name", newMixName: "Name", create: "Add", rename: "Rename", save: "Save", cancel: "Cancel",
    copyFrom: "Copy from", copyFromNone: "Nothing (empty mix)",
    copyFromHint: "Start the new mix with the same sources, levels, pans, mutes and signal points as this mix. Its output is not copied.",
    colour: "Colour", moveToEnd: "Move to end",
    moveToEndHint: "Tracks sit after the IEMs folder. Move the folder and its mixes to the end of the track list.",
    colourHint: "The colour of the IEMs folder and every mix in it.",
    output: "Output", outputNone: "No output",
    deviceClosed: "Audio device closed: channels unknown",
    outputReadOnly: "Several outputs: change in REAPER",
    createCue: "Create cue", repairCue: "Repair cue", cueOutput: "Cue output", cueOutputNeeded: "Cue output: choose the headphones",
    createCueHint: "Make the IEM-Cue track in the IEMs folder, with a send at level 0 from every mix, and turn solo defeat on for it and every mix. IEM Mix listens through it. REAPER undo brings it back.",
    repairCueHint: "A mix has no send to the cue track, or a mix or the cue track has no solo defeat. Add the missing sends at level 0 and turn solo defeat on.",
    cueOutputHint: "The hardware output of the cue track: the engineer’s headphones.",
    cueOutputNeededHint: "The cue track has no hardware output yet. Choose the output the engineer’s headphones are on, or Listen is silent.",
    adopt: "Adopt",
    adoptHint: "Press and hold to move this mix into the IEMs folder, turn its master send off, give it the shared colour and make its sends post-FX pre-fader. This can change what a musician hears. REAPER undo brings it back.",
    adoptNote: "Moves into the IEMs folder, master send off, sends post-FX pre-fader. Can change what a musician hears.",
    delete: "Delete", deleteHint: "Press and hold to delete this mix and its sends. REAPER undo brings it back.",
    holdLegend: "Hold", more: "More", less: "Less",
    moreHint: "Rename, Adopt and Delete. Adopt and Delete act only on a press and hold.",
    panelMixes: "Add mix", panelOutputs: "Outputs", panelFolder: "Folder", panelCue: "Cue", outputsRow: "Outputs", noOutShort: "No out", outputsHint: "Show or hide a row with every mix’s output",
    applying: "Applying…", tracks: "Tracks", unsavedProject: "(unsaved project)",
    cueReady: "The cue track is ready."
  };

  function ui(key) { return UI[key] || ""; }

  function renameLabel(name) { return "Rename mix " + name; }
  function adoptLabel(name) { return "Adopt mix " + name + " into the IEMs folder (press and hold)"; }
  function deleteLabel(name) { return "Delete mix " + name + " (press and hold)"; }

  function chip(phase) { return CHIP[phase] || ""; }
  function banner(phase) { return BANNER[phase] || ""; }

  // Device channels are 0-based in REAPER and numbered from 1 on a mixer.
  function outputText(output) {
    if (!output) return "No output";
    var first = output.channel + 1;
    return output.mono ? "Out " + first + " mono" : "Out " + first + "–" + (first + 1);
  }

  // One picker entry. `names` are the device's channel names (REAPER's, 0-based list); a channel without a name is
  // shown by its number alone, as is everything while the device is closed.
  function channelName(names, channel) {
    var name = names && names[channel];
    return (channel + 1) + (name && name !== String(channel + 1) ? " " + name : "");
  }
  function optionLabel(names, option) {
    if (option.channel === null) return UI.outputNone;
    if (option.mono) return "Mono " + channelName(names, option.channel);
    return "Stereo " + channelName(names, option.channel) + " + " + channelName(names, option.channel + 1);
  }
  // The short form a narrow header shows for a picker's current choice; the open list has the full names.
  function outputShort(output) {
    if (!output) return "None";
    var first = output.channel + 1;
    return output.mono ? "Mono " + first : first + "–" + (first + 1);
  }
  function moreLabel(open, mixName) { return (open ? "Close more for mix " : "More for mix ") + mixName; }
  function outputsStatus(missing) { return missing === 0 ? "All set" : missing + " without output"; }
  function pickerLabel(mixName) { return "Output of mix " + mixName; }
  var CUE_PICKER_LABEL = "Output of the cue track";

  function clashText(clash) {
    return clash["with"] === "master" ? "the master" : "mix " + clash.name;
  }

  function modeText(mode) {
    if (mode === 0) return "Post-fader";
    if (mode === 1) return "Pre-FX";
    return "Not post-FX pre-fader";
  }

  // The tag printed in a cell whose send is not post-FX pre-fader.
  function modeTag(mode) { return mode === 0 ? "POST" : mode === 1 ? "PRE" : "MODE"; }

  function modeNote(mode) {
    return modeText(mode) + " send: IEM Setup makes post-FX pre-fader sends, which ignore the FOH fader.";
  }

  function doubleFeedNote(doubleFeed) {
    return doubleFeed["with"] === "folder"
      ? "Also fed through its folder " + doubleFeed.name + ": this mix hears it twice."
      : "Its child " + doubleFeed.name + " also feeds this mix: it hears that source twice.";
  }

  function cellLabel(row, header, cell) {
    var text = row.name + " to " + header.name + ": ";
    if (!cell) return text + "off";
    return text + "on" + (cell.muted ? ", muted" : "") + (cell.nonStandard ? ", " + modeText(cell.mode) : "")
      + (cell.doubleFeed ? ", double feed" : "");
  }

  // The name of a cell's key while unlocked: what a tap will do.
  function cellAction(row, header, cell) {
    return (cell ? "Switch off " : "Switch on ") + row.name + " to " + header.name;
  }

  function headerFlags(header) {
    var flags = [];
    if (header.stray) flags.push({ code: "stray", text: "Not in IEMs folder" });
    if (header.duplicate) flags.push({ code: "duplicate", text: "Same name as another mix" });
    if (header.noOutput) flags.push({ code: "no-output", text: "No output" });
    if (header.extraOutputs) flags.push({ code: "outputs", text: (header.extraOutputs + 1) + " outputs, read-only" });
    if (header.clashes && header.clashes.length) {
      flags.push({ code: "shared-output", text: "Output shared with " + header.clashes.map(clashText).join(", ") });
    }
    return flags;
  }

  // The sentence under the Cue panel: what the cue track needs now, or that it is ready. `offer` is core.cueOffer.
  function cueStatus(offer) {
    if (!offer.exists) return "No cue track yet. " + UI.createCueHint;
    if (offer.action) return UI.repairCueHint;
    if (offer.needsOutput) return UI.cueOutputNeededHint;
    return UI.cueReady + " " + UI.cueOutputHint;
  }

  // The sentence under the Folder panel. `offer` is core.folderOffer.
  function folderNote(offer) {
    return offer.moveToEnd ? UI.colourHint + " " + UI.moveToEndHint : UI.colourHint;
  }

  // What a cell tag means, printed under the grid while a tag is on screen (a tooltip is invisible on touch).
  function modeLegend(mode) {
    if (mode === 0) return "post-fader send: it follows the FOH fader";
    if (mode === 1) return "pre-FX send";
    return "send that is not post-FX pre-fader";
  }
  var DOUBLE_LEGEND = "a folder and its child both feed this mix: it hears the source twice";

  function emptyMatrix(state) {
    if (!state.sources.length && !state.mixes.length) return "This project has no tracks yet.";
    if (!state.mixes.length) return "No in-ear mixes yet. A mix is a track named IEM_ followed by a name. Add one with Add mix above.";
    return "";
  }

  // The strip above the grid: one short status per setup panel, so a panel only opens when it has something to do.
  function mixesStatus(count) { return count === 0 ? "None yet" : count === 1 ? "1 mix" : count + " mixes"; }
  function folderStatus(offer) { return !offer || !offer.exists ? "None yet" : offer.moveToEnd ? "Tracks after it" : "Ready"; }
  function cueSummary(offer) {
    if (!offer || !offer.exists) return "Not made yet";
    if (offer.action) return "Needs repair";
    if (offer.needsOutput) return "Choose output";
    return "Ready";
  }

  function noMatch(filter) { return "No track matches “" + filter + "”."; }

  return { error: error, ui: ui, renameLabel: renameLabel, deleteLabel: deleteLabel, adoptLabel: adoptLabel, chip: chip, banner: banner, outputText: outputText, outputShort: outputShort, moreLabel: moreLabel, outputsStatus: outputsStatus, optionLabel: optionLabel, pickerLabel: pickerLabel, cuePickerLabel: CUE_PICKER_LABEL, clashText: clashText, modeText: modeText, modeTag: modeTag,
    modeNote: modeNote, modeLegend: modeLegend, doubleLegend: DOUBLE_LEGEND, cueStatus: cueStatus, folderNote: folderNote, doubleFeedNote: doubleFeedNote, cellLabel: cellLabel, cellAction: cellAction, headerFlags: headerFlags,
    emptyMatrix: emptyMatrix, noMatch: noMatch, mixesStatus: mixesStatus, folderStatus: folderStatus, cueSummary: cueSummary };
});
