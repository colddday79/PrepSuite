import type { Delivery } from "./prompts.ts";

/** Observations use measured acoustic values, never guesses about emotions. */
export function deliverySummary(d: Delivery | null): string {
  if (!d) return "No voice measurements were available for this answer.";
  if (d.duration_s <= 0 || d.words === 0) return "Too little recognized speech to measure delivery reliably.";
  const pace = Math.round(d.wpm);
  const observations = [`Measured pace: about ${pace} words per minute.`];
  if (d.wpm > 170) observations.push("Try a short pause between your main points.");
  else if (d.longest_pause_s >= 3) {
    observations.push(`The longest measured pause was ${d.longest_pause_s.toFixed(1)} seconds; plan your next point before recording.`);
  } else if (d.filler_count / (d.duration_s / 60) >= 3 && d.filler_count >= 3) {
    observations.push(`${d.filler_count} filler words were found in the transcript; try replacing one with a pause.`);
  } else if (d.trailing_off) {
    observations.push("The measured volume fell at the end; keep the microphone distance steady and finish the sentence audibly.");
  } else if (d.pitch_hz_mean !== null && d.pitch_semitone_sd !== null && d.monotone === true) {
    observations.push(`Measured pitch variation was ${d.pitch_semitone_sd.toFixed(1)} semitones; emphasize the key words in your example.`);
  } else if (d.wpm > 0 && d.wpm < 100) {
    observations.push("Try connecting the situation, your action, and the result with fewer gaps.");
  }
  return observations.join(" ");
}
