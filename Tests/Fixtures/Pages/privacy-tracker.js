// What a third party's script does on the privacy fixture: says it ran.
(window.loaded = window.loaded || []).push(document.currentScript && new URL(document.currentScript.src).hostname);
document.getElementById("out").textContent = "ran: " + window.loaded.join(", ");
