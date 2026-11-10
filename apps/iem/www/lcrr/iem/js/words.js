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
    track_gone: "That track is no longer in the project. The page has been refreshed; try again.",
    not_a_mix: "That track isn’t a mix any more. The page has been refreshed; try again.",
    not_the_folder: "That isn’t the IEMs folder any more. The page has been refreshed; try again.",
    nothing_to_move: "Nothing sits after the IEMs folder, so there is nothing to move.",
    multiple_outputs: "That mix has more than one hardware output, so it is read-only here. Change it in REAPER.",
    bad_channel: "That output channel is not on the audio device. The page has been refreshed; pick again.",
    no_device: "The audio device is closed, so its channels are not known. Open it in REAPER to pick an output.",
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
    unlock: "Unlock", lock: "Lock",
    unlockHint: "Locked: unlock to create or rename mixes.", unlockedHint: "Unlocked: changes go straight into REAPER, one undo step each.",
    newMix: "New mix", newMixName: "Name", create: "Create", rename: "Rename", save: "Save", cancel: "Cancel",
    colour: "Colour", moveToEnd: "Move to end",
    moveToEndHint: "Tracks sit after the IEMs folder. Move the folder and its mixes to the end of the track list.",
    colourHint: "The colour of the IEMs folder and every mix in it.",
    output: "Output", outputNone: "No output",
    deviceClosed: "Audio device closed: channels unknown",
    outputReadOnly: "Several outputs: change in REAPER",
    delete: "Delete", deleteHint: "Press and hold to delete this mix and its sends. REAPER undo brings it back."
  };

  function ui(key) { return UI[key] || ""; }

  function renameLabel(name) { return "Rename mix " + name; }
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
  function pickerLabel(mixName) { return "Output of mix " + mixName; }

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
    return text + cell.db + " dB" + (cell.muted ? ", muted" : "") + (cell.nonStandard ? ", " + modeText(cell.mode) : "")
      + (cell.doubleFeed ? ", double feed" : "");
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

  function emptyMatrix(state) {
    if (!state.sources.length && !state.mixes.length) return "This project has no tracks yet.";
    if (!state.mixes.length) return "No in-ear mixes yet. A mix is a track named IEM_ followed by a name.";
    return "";
  }

  function noMatch(filter) { return "No track matches “" + filter + "”."; }

  return { error: error, ui: ui, renameLabel: renameLabel, deleteLabel: deleteLabel, chip: chip, banner: banner, outputText: outputText, optionLabel: optionLabel, pickerLabel: pickerLabel, clashText: clashText, modeText: modeText, modeTag: modeTag,
    modeNote: modeNote, doubleFeedNote: doubleFeedNote, cellLabel: cellLabel, headerFlags: headerFlags,
    emptyMatrix: emptyMatrix, noMatch: noMatch };
});
