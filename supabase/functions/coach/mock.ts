// Deterministic, job-aware stand-in for Claude. Used when no Anthropic key is
// configured or COACH_MOCK=1, so the app can be tested end to end for free.
// Same response shapes as the live path, no randomness: same input, same output.

import type {
  Delivery,
  FeedbackInput,
  FeedbackResult,
  QuestionItem,
  QuestionsResult,
  WrapupInput,
  WrapupResult,
} from "./prompts.ts";

type Q = Omit<QuestionItem, "id">;

interface Role {
  match: RegExp;
  title: string;
  noun: string;
  scenarios: [Q, Q];
  note: string;
}

// Checked in order; the first match wins. Job text is lower-cased and
// stripped of accents before matching, so "café" matches "cafe".
const ROLES: Role[] = [
  {
    match: /\b(barista|coffee|cafe|cafes|espresso|starbucks|costa)\b/,
    title: "Barista at a busy café",
    noun: "barista",
    scenarios: [
      {
        text: "The queue is out the door and a customer says their latte is wrong; what do you do?",
        focus: "Staying calm with an unhappy customer",
      },
      {
        text: "How would you keep every drink right when the café is at its busiest?",
        focus: "Quality under time pressure",
      },
    ],
    note: "Know two or three drinks on their menu.",
  },
  {
    match: /\b(nurse|nursing|midwife)\b/,
    title: "Nurse",
    noun: "nurse",
    scenarios: [
      {
        text: "A patient's relative is upset about waiting and starts raising their voice; what do you do?",
        focus: "Calm communication under stress",
      },
      {
        text: "How do you make sure nothing gets missed when you hand over to the next shift?",
        focus: "Patient safety and attention to detail",
      },
    ],
    note: "Have one patient-care example ready.",
  },
  {
    match: /\b(carer|care assistant|care worker|care home|support worker|healthcare assistant|hca)\b/,
    title: "Care assistant",
    noun: "care assistant",
    scenarios: [
      {
        text: "Someone you care for refuses help getting washed; how would you handle it?",
        focus: "Respect, patience and dignity",
      },
      {
        text: "How would you notice that someone you look after is becoming unwell?",
        focus: "Observation and reporting concerns",
      },
    ],
    note: "Have one example of being patient with someone.",
  },
  {
    match: /\b(teaching assistant|classroom assistant|learning support)\b/,
    title: "Teaching assistant",
    noun: "teaching assistant",
    scenarios: [
      {
        text: "A child keeps distracting others during a lesson; what would you do?",
        focus: "Managing behaviour calmly",
      },
      {
        text: "How would you help a pupil who is falling behind with reading?",
        focus: "Supporting different learners",
      },
    ],
    note: "Have one example of helping someone learn.",
  },
  {
    match: /\b(teacher|teaching|tutor|tutoring|lecturer)\b/,
    title: "Teacher",
    noun: "teacher",
    scenarios: [
      { text: "A student keeps disrupting your class; how do you handle it?", focus: "Behaviour management" },
      {
        text: "How would you plan a lesson for a class with very mixed abilities?",
        focus: "Planning for different learners",
      },
    ],
    note: "Have one lesson or teaching moment ready to describe.",
  },
  {
    match:
      /\b(software|developer|programmer|programming|coding|coder|frontend|backend|full stack|web dev|app dev|devops)\b/,
    title: "Junior software developer",
    noun: "software developer",
    scenarios: [
      {
        text: "Tell me about a bug you tracked down and how you found the cause.",
        focus: "Debugging and problem solving",
      },
      { text: "How would you handle a code review comment you disagreed with?", focus: "Taking feedback and teamwork" },
    ],
    note: "Be ready to explain one project you built, simply.",
  },
  {
    match: /\b(warehouse|picker|packer|forklift|logistics|fulfilment|fulfillment|stockroom|amazon)\b/,
    title: "Warehouse operative",
    noun: "warehouse operative",
    scenarios: [
      { text: "You see a colleague lifting heavy boxes in an unsafe way; what do you do?", focus: "Safety awareness" },
      { text: "How would you keep your pick rate up without making mistakes?", focus: "Speed with accuracy" },
    ],
    note: "Mention safety at least once.",
  },
  {
    match: /\b(chef|cook|kitchen|sous|kitchen porter)\b/,
    title: "Kitchen team member",
    noun: "kitchen team member",
    scenarios: [
      {
        text: "The kitchen is behind on orders and the head chef is stressed; how do you help?",
        focus: "Teamwork under pressure",
      },
      {
        text: "How do you keep food safe and your station clean during a busy service?",
        focus: "Hygiene and food safety",
      },
    ],
    note: "Mention food safety and keeping your station clean.",
  },
  {
    match:
      /\b(waiter|waitress|waiting staff|server|restaurant|bartender|bar staff|barman|barmaid|pub|hospitality|front of house|hostess|hotel)\b/,
    title: "Restaurant server",
    noun: "server",
    scenarios: [
      {
        text: "A table says their food is cold and they are not happy; how do you respond?",
        focus: "Recovering a bad customer experience",
      },
      {
        text: "How do you keep track of several tables at once on a busy night?",
        focus: "Multitasking and organisation",
      },
    ],
    note: "Smile, and have a customer-service example ready.",
  },
  {
    match:
      /\b(customer service|call center|call centre|contact center|contact centre|help desk|helpdesk|customer support)\b/,
    title: "Customer service advisor",
    noun: "customer service advisor",
    scenarios: [
      {
        text: "A caller is angry because their problem still isn't fixed; walk me through how you handle the call.",
        focus: "Calming things down and solving it",
      },
      {
        text: "How would you explain something complicated to a customer in simple words?",
        focus: "Clear communication",
      },
    ],
    note: "Have one example of calming someone down.",
  },
  {
    match:
      /\b(retail|shop|store|cashier|checkout|till|sales assistant|shop assistant|supermarket|tesco|walmart|clothing)\b/,
    title: "Retail sales assistant",
    noun: "sales assistant",
    scenarios: [
      {
        text: "A customer wants a refund without a receipt and is getting annoyed; how do you handle it?",
        focus: "Handling a difficult customer",
      },
      {
        text: "The shop is quiet and your tasks are done; what would you do with the time?",
        focus: "Using your initiative",
      },
    ],
    note: "Look around the shop or website before you go.",
  },
  {
    match: /\b(receptionist|reception|front desk)\b/,
    title: "Receptionist",
    noun: "receptionist",
    scenarios: [
      {
        text: "The phone is ringing, someone is waiting at the desk and an urgent email arrives; what do you do first?",
        focus: "Prioritising under pressure",
      },
      {
        text: "A visitor arrives upset because nobody told them their meeting was cancelled; what do you say?",
        focus: "First impressions and calm communication",
      },
    ],
    note: "First impressions count: greet them warmly.",
  },
  {
    match: /\b(admin|administrator|administrative|office|secretary|clerk|data entry)\b/,
    title: "Office administrator",
    noun: "administrator",
    scenarios: [
      {
        text: "You have three urgent requests from different people at once; how do you decide what to do first?",
        focus: "Prioritising and organisation",
      },
      { text: "How do you keep your work accurate when the tasks are repetitive?", focus: "Attention to detail" },
    ],
    note: "Have one example of being organised.",
  },
  {
    match: /\b(marketing|social media|content creator|advertising|copywriter|brand)\b/,
    title: "Marketing assistant",
    noun: "marketing assistant",
    scenarios: [
      { text: "How would you tell whether one of our social media posts actually worked?", focus: "Measuring results" },
      {
        text: "Pick a brand you like; what is one thing their marketing does well?",
        focus: "Marketing judgement and curiosity",
      },
    ],
    note: "Look at their social media before you go.",
  },
  {
    match: /\b(data analyst|data|analyst|analytics|excel|sql)\b/,
    title: "Data analyst",
    noun: "data analyst",
    scenarios: [
      { text: "Tell me about a time you found something surprising in some numbers.", focus: "Curiosity with data" },
      { text: "How would you explain a finding to someone who hates numbers?", focus: "Explaining insights simply" },
    ],
    note: "Be ready to explain one analysis in plain words.",
  },
  {
    match: /\b(driver|driving|delivery|courier|van|lorry|truck|deliveroo)\b/,
    title: "Delivery driver",
    noun: "delivery driver",
    scenarios: [
      {
        text: "You are running late on your route and a customer isn't home; what do you do?",
        focus: "Problem solving on the road",
      },
      { text: "How do you stay safe and focused on a long shift?", focus: "Safety and reliability" },
    ],
    note: "Mention safety and being on time.",
  },
  {
    match: /\b(sales|salesperson|sales rep|account executive|business development|telesales)\b/,
    title: "Sales representative",
    noun: "sales representative",
    scenarios: [
      { text: "A customer says our price is too high; how do you respond?", focus: "Handling objections" },
      {
        text: "How would you follow up with someone who went quiet after showing interest?",
        focus: "Persistence without being pushy",
      },
    ],
    note: "Know what they sell and who buys it.",
  },
  {
    match: /\b(cleaner|cleaning|housekeeping|housekeeper|janitor|custodian)\b/,
    title: "Cleaner",
    noun: "cleaner",
    scenarios: [
      {
        text: "You are running out of time and two rooms are still left; what do you do?",
        focus: "Managing time and standards",
      },
      { text: "How do you make sure you never miss anything when cleaning a room?", focus: "Attention to detail" },
    ],
    note: "Mention reliability and doing things properly.",
  },
  {
    match: /\b(security|guard|door supervisor|bouncer)\b/,
    title: "Security officer",
    noun: "security officer",
    scenarios: [
      {
        text: "Someone becomes aggressive when you refuse them entry; what do you do?",
        focus: "Calm handling of conflict",
      },
      { text: "How do you stay alert on a long, quiet shift?", focus: "Alertness and reliability" },
    ],
    note: "Stress calm, safe handling of conflict.",
  },
];

const GENERIC_SCENARIOS: [Q, Q] = [
  {
    text: "What do you think a normal day in this job involves, and which part would you be best at?",
    focus: "Understanding what the job involves",
  },
  {
    text: "If several urgent tasks landed on you at once, how would you decide what to do first?",
    focus: "Prioritising under pressure",
  },
];

const FILLER_WORDS =
  /\b(um+|uh+|erm+|er|ah+|like|you know|kind of|sort of|basically|actually|really|so|yeah|okay|ok|well|just)\b/g;

function fold(text: string): string {
  return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

function article(noun: string): string {
  return /^[aeiou]/i.test(noun) ? "an" : "a";
}

function capitalise(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/** Pull a role phrase out of speech like "um I'm going for like a graphic designer job". */
function extractRolePhrase(job: string): string | null {
  const t = fold(job).replace(/[^a-z\s'-]/g, " ").replace(FILLER_WORDS, " ").replace(/\s+/g, " ").trim();
  if (!t) return null;
  const m = t.match(
    /\b(?:applying for|apply for|going for|interviewing for|interview for|job as|role as|position as|work as|working as|become|want to be|wanna be|hoping to be|applying to be|apply to be)\s+(?:an?\s+|the\s+|my\s+)?(.+)$/,
  ) ?? t.match(/\b(?:an?|the)\s+([a-z' -]+?)\s+(?:job|role|position)\b/);
  let phrase = m ? m[1] : t.split(" ").length <= 4 ? t : "";
  phrase = phrase.split(/\b(?:job|role|position|at|in|with|for|because|and|but|which|that|where|i|i'm|im)\b/)[0].trim();
  const words = phrase.split(" ").filter((w) => w.length > 1 && !/^(an?|the|my|some|to)$/.test(w)).slice(0, 4);
  return words.length ? words.join(" ") : null;
}

export function inferRole(job: string): { title: string; noun: string | null; scenarios: [Q, Q]; note: string | null } {
  const folded = fold(job);
  for (const role of ROLES) {
    if (role.match.test(folded)) return role;
  }
  const phrase = extractRolePhrase(job);
  if (phrase) return { title: capitalise(phrase), noun: phrase, scenarios: GENERIC_SCENARIOS, note: null };
  return { title: "General job interview", noun: null, scenarios: GENERIC_SCENARIOS, note: null };
}

export function mockQuestions(job: string, count: number): QuestionsResult {
  const role = inferRole(job);
  const motivation: Q = role.noun
    ? {
      text: `Why do you want to work as ${article(role.noun)} ${role.noun}, and why here?`,
      focus: "Motivation for this job",
    }
    : { text: "Why do you want this job, and why here?", focus: "Motivation for this job" };
  const pool: Q[] = [
    motivation,
    role.scenarios[0],
    {
      text: "Tell me about a time you worked with other people to sort out a problem.",
      focus: "Teamwork and problem solving",
    },
    {
      text: "Tell me about a time you learned something new quickly, at school, in a hobby, or anywhere else.",
      focus: "Learning fast, no work history needed",
    },
    role.scenarios[1],
    {
      text: "What is one strength you would bring to this job, and when have you shown it?",
      focus: "A real strength, with proof",
    },
    { text: "How do you stay calm and organised when there is a lot to do at once?", focus: "Handling pressure" },
    { text: "What would you want to have learned after your first three months here?", focus: "Motivation to grow" },
  ];
  return {
    job_title: role.title,
    questions: pool.slice(0, count).map((q, i) => ({ id: `q${i + 1}`, ...q })),
  };
}

// ---------------------------------------------------------------------------
// Feedback
// ---------------------------------------------------------------------------

interface Token {
  text: string;
  start: number;
  end: number;
}

function tokens(text: string): Token[] {
  return [...text.matchAll(/\S+/g)].map((m) => ({ text: m[0], start: m.index!, end: m.index! + m[0].length }));
}

/** Exact substring of the transcript covering `len` words starting at word `from`. */
function quote(transcript: string, toks: Token[], from: number, len = 12): string {
  if (!toks.length) return "";
  const a = Math.max(0, Math.min(from, toks.length - 1));
  const b = Math.min(toks.length - 1, a + len - 1);
  return transcript
    .slice(toks[a].start, toks[b].end)
    .replace(/(?:[,;:]?\s+(?:and|but|so|or|then|the|a|an|to|because|which|where))+$/i, "")
    .replace(/[,;:]$/, "");
}

const NUMBER_WORDS = [
  "No",
  "One",
  "Two",
  "Three",
  "Four",
  "Five",
  "Six",
  "Seven",
  "Eight",
  "Nine",
  "Ten",
  "Eleven",
  "Twelve",
];

function countWord(n: number): string {
  const r = Math.round(n);
  return r < NUMBER_WORDS.length ? NUMBER_WORDS[r] : String(r);
}

function overTime(seconds: number): string {
  if (seconds < 50) return `in ${Math.max(1, Math.round(seconds))} seconds`;
  if (seconds < 90) return "in about a minute";
  return `in about ${Math.round(seconds / 60)} minutes`;
}

export function describeDelivery(d: Delivery | null): string {
  if (!d) return "No delivery measurements came through for this answer.";
  const obs: string[] = [];
  const wpm = Math.round(d.wpm);
  if (d.wpm > 170) obs.push(`About ${wpm} words a minute is fast; slow down.`);
  else if (d.wpm > 0 && d.wpm < 100) obs.push(`About ${wpm} words a minute is on the slow side.`);

  const minutes = d.duration_s / 60;
  const perMinute = minutes > 0 ? d.filler_count / minutes : 0;
  if (d.filler_count >= 3 && perMinute >= 3) {
    const top = Object.entries(d.fillers).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0];
    const mostly = top && top[1] * 2 >= d.filler_count ? ` (mostly "${top[0]}")` : "";
    obs.push(`${countWord(d.filler_count)} filler words${mostly} ${overTime(d.duration_s)}.`);
  }
  if (d.trailing_off) obs.push("Your volume dropped at the end.");
  if (d.monotone === true) obs.push("Pitch barely moved, so it sounded flat.");
  if (d.longest_pause_s >= 3) obs.push(`The longest pause was about ${Math.round(d.longest_pause_s)} seconds.`);
  if (d.loudness_db_mean < -38) obs.push("It was quite quiet overall.");
  if (d.speech_ratio < 0.6) obs.push("There was a lot of silence between bits of speech.");

  if (obs.length) return obs.slice(0, 2).join(" ");
  return wpm > 0
    ? `Steady: about ${wpm} words a minute with no long pauses or runs of fillers.`
    : "Too little speech to say much about how it sounded.";
}

type Problem = "short" | "personal" | "example" | "result" | "rambling" | "fillers" | "fast" | "none";

export function mockFeedback(input: FeedbackInput): FeedbackResult {
  const transcript = input.transcript.trim();
  const toks = tokens(transcript);
  const wc = toks.length;
  const d = input.delivery;
  const delivery = describeDelivery(d);

  if (wc < 8) {
    return {
      headline: wc === 0
        ? "Nothing came through, so there is nothing to judge."
        : "Too short to judge. Try that one again.",
      problem: wc === 0
        ? "The transcript is empty, so either the mic missed you or the answer never started."
        : `You only said ${wc} word${wc === 1 ? "" : "s"}, which does not answer the question.`,
      evidence: wc === 0 ? "" : transcript,
      fix: "Record it again and talk for at least 30 seconds: what happened, what you did, and how it ended.",
      delivery: wc === 0 ? "No speech to judge." : delivery,
      strength: "Nothing to go on yet; one real attempt will get you proper feedback.",
    };
  }

  const lower = fold(transcript);
  const words = lower.split(/\s+/);
  const iCount = words.filter((w) => /^(i|i'm|i've|i'd|im|my|me)[.,!?]?$/.test(w)).length;
  const weIndex = words.findIndex((w) => /^(we|we're|we've|our|us)[.,!?]?$/.test(w));
  const weCount = words.filter((w) => /^(we|we're|we've|our|us)[.,!?]?$/.test(w)).length;
  const hasExample =
    /\b(one time|once|last (year|summer|month|week|christmas)|when i was|for example|for instance|there was a time|at my (last|old|previous)|at school|at college|at uni|in my (last|old|previous))\b/
      .test(lower);
  const hasAction =
    /\b(i|so i|then i)\s+(did|made|took|asked|helped|decided|organised|organized|started|built|fixed|talked|spoke|explained|trained|led|handled|sorted|called|stayed|offered|suggested|checked|set up|wrote|found|showed|covered)\b/
      .test(lower);
  const hasResult =
    /\b(result|so that|in the end|ended up|which meant|turned out|finally|afterwards|managed to|improved|increased|reduced|saved|fixed|solved|learned|learnt|thanked|got better|happy|worked out)\b/
      .test(lower) ||
    /\d+\s?(%|percent)/.test(lower);
  const minutes = d ? d.duration_s / 60 : 0;
  const fillersPerMinute = d && minutes > 0 ? d.filler_count / minutes : 0;

  let problem: Problem = "none";
  if (wc < 40) problem = "short";
  else if (weCount >= 3 && weCount > iCount * 1.5) problem = "personal";
  else if (!hasExample && !hasAction) problem = "example";
  else if (!hasResult) problem = "result";
  else if (wc > 320 || (d !== null && d.duration_s > 150)) problem = "rambling";
  else if (fillersPerMinute >= 6) problem = "fillers";
  else if (d !== null && d.wpm > 185) problem = "fast";

  const fillerIndex = words.findIndex((w) => /^(um+|uh+|erm+|er|like)[.,!?]?$/.test(w));
  const role = inferRole(input.job);
  const jobPhrase = role.noun ? `${role.noun} job` : "job";

  const out: Record<Problem, Omit<FeedbackResult, "delivery" | "strength">> = {
    short: {
      headline: "Too short. You stopped before the good part.",
      problem: `You stopped after ${wc} words, before giving any real detail or example.`,
      evidence: quote(transcript, toks, 0),
      fix: "Add one real example: what happened, what you did, and how it ended. Aim for 45 to 90 seconds.",
    },
    personal: {
      headline: "Good story, but where are you in it?",
      problem: 'It is all "we", so the interviewer cannot tell what you did yourself.',
      evidence: quote(transcript, toks, Math.max(0, weIndex - 2)),
      fix: 'Say "I" for the parts that were you, like "I [what you did]", and name at least two things you did.',
    },
    example: {
      headline: "Sounds fine, but there is no real example.",
      problem: "It stays general. There is no specific moment to back up what you are saying.",
      evidence: quote(transcript, toks, 0),
      fix: 'Pick one real moment and tell it: "One time at [place], [what happened], so I [what you did]."',
    },
    result: {
      headline: "Decent example, but it has no ending.",
      problem: "You explain what happened but never say how it ended or what changed.",
      evidence: quote(transcript, toks, Math.max(0, wc - 12)),
      fix: 'Finish with the outcome in one line: "In the end, [what changed]."',
    },
    rambling: {
      headline: "Good material, but it goes on too long.",
      problem: "The answer runs long and the main point gets buried.",
      evidence: quote(transcript, toks, Math.floor(wc / 2)),
      fix: "Cut it to three parts: the situation in one line, what you did, and how it ended. Then stop.",
    },
    fillers: {
      headline: "Fillers are drowning out a decent answer.",
      problem: "The content is fine, but the filler words get in the way of it.",
      evidence: fillerIndex >= 0 ? quote(transcript, toks, Math.max(0, fillerIndex - 3), 10) : "",
      fix: 'When you feel an "um" coming, pause silently instead. A short pause sounds more thoughtful.',
    },
    fast: {
      headline: "Good answer, but slow down.",
      problem: "The content is solid, but it came out too fast to take in.",
      evidence: "",
      fix: "Take a breath between each part of the answer and aim for about 140 words a minute.",
    },
    none: {
      headline: "Strong answer. Tie it back to the job.",
      problem: "The example works; the only gap is that you never link it back to this job.",
      evidence: "",
      fix: `Finish with one line like "That is why I would be good at [part of this ${jobPhrase}]."`,
    },
  };

  const strengths: [boolean, string][] = [
    [hasExample && problem !== "example", "You used a real example instead of talking in general."],
    [hasAction && problem !== "personal", "You were clear about what you did yourself."],
    [hasResult && problem !== "result", "You gave the story an ending."],
    [d !== null && d.wpm >= 115 && d.wpm <= 165, "Your pace was easy to follow."],
    [d !== null && d.filler_count <= 1 && problem !== "fillers", "Hardly any filler words."],
  ];
  const strength = strengths.find(([ok]) => ok)?.[1] ??
    "You kept going to the end, which gives you something to build on.";

  return { ...out[problem], delivery, strength };
}

// ---------------------------------------------------------------------------
// Wrap-up
// ---------------------------------------------------------------------------

const PATTERNS: { key: string; test: RegExp; tip: string; note: string }[] = [
  {
    key: "personal",
    test: /\bwe\b|what you did yourself|where are you/,
    tip: 'Say "I" for the parts you did yourself, not "we".',
    note: 'Say "I", not "we".',
  },
  {
    key: "result",
    test: /ending|how it ended|what changed|no result|outcome/,
    tip: "Finish every example by saying how it ended.",
    note: "Always say how it ended.",
  },
  {
    key: "example",
    test: /no real example|general|specific moment|vague/,
    tip: "Back every claim with one real moment: where you were, what happened, what you did.",
    note: "One real example per answer.",
  },
  {
    key: "short",
    test: /too short|stopped after|only said/,
    tip: "Give each answer at least 45 seconds; one proper example beats a quick line.",
    note: "Don't stop too early.",
  },
  {
    key: "rambling",
    test: /too long|runs long|buried|rambl/,
    tip: "Keep answers to three parts and stop once you have said how it ended.",
    note: "Three parts, then stop.",
  },
  {
    key: "fillers",
    test: /filler|\bums?\b/,
    tip: "Swap fillers for a short silent pause; it sounds more thoughtful.",
    note: 'Pause instead of "um".',
  },
  {
    key: "pace",
    test: /fast|slow down|rushed/,
    tip: "Slow down to about 140 words a minute and breathe between points.",
    note: "Slow down; breathe between points.",
  },
  {
    key: "flat",
    test: /flat|pitch/,
    tip: "Lift your voice on the key words so it does not sound flat.",
    note: "Lift your voice on key words.",
  },
  {
    key: "volume",
    test: /volume dropped|quiet/,
    tip: "Keep your volume up through the last sentence.",
    note: "Finish sentences loud and clear.",
  },
];

export function mockWrapup(input: WrapupInput): WrapupResult {
  const role = inferRole(input.job);
  const counts = PATTERNS.map((p, order) => ({
    p,
    order,
    n: input.answers.filter((a) => p.test.test(fold(`${a.headline} ${a.problem} ${a.delivery}`))).length,
  }))
    .filter((c) => c.n > 0)
    .sort((a, b) => b.n - a.n || a.order - b.order);

  const jobPhrase = role.noun ? `this ${role.noun} job` : "this job";
  const tips = counts.slice(0, 3).map((c) => c.p.tip);
  const defaultTips = [
    `End each answer with one line on why it makes you right for ${jobPhrase}.`,
    "Before each answer, take a second to pick the one example you will use.",
    "Have one question ready to ask them, such as what the first few weeks look like.",
  ];
  for (const t of defaultTips) if (tips.length < 4) tips.push(t);

  const notes = ["Breathe, then answer: what happened, what you did, how it ended."];
  for (const c of counts.slice(0, 2)) notes.push(c.p.note);
  if (role.note) notes.push(role.note);
  notes.push(`Know your one-line answer to "why ${jobPhrase}?"`, "Bring one question to ask them.");

  const stories: string[] = [];
  for (const a of input.answers) {
    if (stories.length >= 3) break;
    const t = a.transcript.trim();
    const toks = tokens(t);
    // "I" plus a past-tense action marks a real story; quote from there.
    const action =
      /\bi\s+(\w+ed|was|did|had|made|took|ran|led|built|taught|found|got|went|gave|kept|told|spoke|sold|wrote|brought|dealt|set up)\b/
        .exec(fold(t));
    if (toks.length < 25 || !action) continue;
    const from = fold(t).slice(0, action.index).split(/\s+/).filter(Boolean).length;
    const q = a.question.length > 60 ? `${a.question.slice(0, 57).trimEnd()}...` : a.question;
    stories.push(`Your example from "${q}": "${quote(t, toks, from, 14)}"`);
  }

  return { tips: tips.slice(0, 5), last_minute_notes: notes.slice(0, 6), stories_to_use: stories };
}
