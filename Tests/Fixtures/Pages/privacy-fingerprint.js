// What a fingerprinting script does: draws text on a canvas and reads the pixels back.
(window.loaded = window.loaded || []).push("fingerprint");
const canvas = document.createElement("canvas");
const context = canvas.getContext("2d");
context.fillText("Cwm fjordbank glyphs vext quiz", 2, 15);
canvas.toDataURL();
