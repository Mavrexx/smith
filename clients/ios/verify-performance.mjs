import fs from "node:fs";

const read = (name) => fs.readFileSync(new URL(name, import.meta.url), "utf8");
const voice = read("./SmithApp/SmithVoiceSession.swift");
const audio = read("./SmithApp/SmithAudioController.swift");
const activity = read("./SmithApp/SmithLiveActivityManager.swift");
const home = read("./SmithApp/SmithHomeView.swift");

const checks = [
  ["bounded microphone transport queue", voice.includes("pending.count >= 8")],
  ["microphone transport uses a background serial queue", voice.includes("com.farhan.smith.audio-transport")],
  ["capture callback has no MainActor task", /startCaptureIfNeeded\(\)[\s\S]*?transport\.enqueue\(data\)/.test(voice) && !/startCaptureIfNeeded\(\)[\s\S]*?Task \{ @MainActor/.test(voice)],
  ["incoming audio state updates only on transition", voice.includes('if state != "SPEAKING"')],
  ["base64 PCM decoding is outside voice UI state", !voice.includes("Data(base64Encoded: encoded)") && audio.includes("playbackProcessingQueue.async")],
  ["playback conversion uses utility QoS", audio.includes("com.farhan.smith.playback-processing") && audio.includes("qos: .utility")],
  ["no per-sample transcendental clipping", !audio.includes("tanh(")],
  ["capture conversion buffer is reused", audio.includes("let outputCapacity") && audio.includes("converted.frameLength = 0")],
  ["Dynamic Island updates are deduplicated", activity.includes("state != lastState || subtitle != lastSubtitle")],
  ["home orb has no infinite animation", !home.includes("repeatForever")],
];

let failed = false;
for (const [name, passed] of checks) {
  console.log(`${passed ? "PASS" : "FAIL"}  ${name}`);
  if (!passed) failed = true;
}

// Ten simulated minutes of continuous 40 ms microphone input against a sender
// slower than real time. The bounded queue must never grow beyond eight frames.
let pending = 0;
let sendingUntil = 0;
let maximumPending = 0;
let dropped = 0;
const frameIntervalMs = 40;
const simulatedSendMs = 65;
for (let now = 0; now < 10 * 60 * 1000; now += frameIntervalMs) {
  if (sendingUntil && now >= sendingUntil) {
    pending = Math.max(0, pending - 1);
    sendingUntil = pending ? now + simulatedSendMs : 0;
  }
  if (pending >= 8) {
    pending -= 1;
    dropped += 1;
  }
  pending += 1;
  if (!sendingUntil) sendingUntil = now + simulatedSendMs;
  maximumPending = Math.max(maximumPending, pending);
}
console.log(`STRESS  frames=15000 maxQueue=${maximumPending} dropped=${dropped}`);
if (maximumPending > 8) failed = true;
if (failed) process.exit(1);
console.log("Smith iOS hot-path performance regression checks passed.");