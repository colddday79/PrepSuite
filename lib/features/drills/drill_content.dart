/// The skill path: four small skills, two short lessons each, written and reviewed by hand. It is
/// static and offline (no coach calls), and every example comes from school, volunteering, clubs,
/// part-time jobs or personal projects, so it fits someone who has never had a paid job.
///
/// These are quiet text exercises. Finishing one shows the idea was understood; it is not spoken
/// progress, so each lesson ends by offering a spoken try.
library;

/// The five kinds of exercise, each one a set of boxes to answer.
enum DrillKind { choice, oddOneOut, fillBlank, order, rewrite }

class DrillSkill {
  const DrillSkill({required this.id, required this.title, required this.summary, required this.lessons});

  final String id;
  final String title;

  /// One line under the title on the skill path.
  final String summary;
  final List<DrillLesson> lessons;
}

class DrillLesson {
  const DrillLesson({required this.id, required this.title, required this.takeaway, required this.exercises});

  final String id;
  final String title;

  /// The one idea to remember, shown when the lesson is done.
  final String takeaway;
  final List<DrillExercise> exercises;

  /// Exercises with a right answer. The rewrite is practice, so it is not scored.
  int get scoredCount => exercises.where((e) => e.scored).length;

  /// About half a minute per exercise.
  int get minutes => (exercises.length / 2).ceil();
}

/// One exercise. [instruction] is the short line above the prompt that says what to do (each kind
/// has its own, "Fill in the blank"), [prompt] is the question itself, and [asked] is the
/// interviewer's line it is about, if any.
sealed class DrillExercise {
  const DrillExercise({required this.id, required this.instruction, required this.prompt, this.asked});

  /// Stable across releases: progress and tests refer to it.
  final String id;
  final String instruction;
  final String prompt;
  final String? asked;

  DrillKind get kind;

  /// Whether the exercise has a right answer that counts toward "right first time".
  bool get scored => true;
}

/// A prompt and three or four answer boxes with one best answer.
final class ChoiceExercise extends DrillExercise {
  const ChoiceExercise({
    required super.id,
    super.instruction = 'Choose the best answer',
    required super.prompt,
    super.asked,
    required this.options,
    required this.answer,
    required this.why,
  });

  final List<String> options;

  /// Index into [options].
  final int answer;

  /// One sentence shown after checking.
  final String why;

  @override
  DrillKind get kind => DrillKind.choice;
}

/// An answer split into sentence boxes; one of them doesn't belong.
final class OddOneOutExercise extends DrillExercise {
  const OddOneOutExercise({
    required super.id,
    super.instruction = "Tap the sentence that doesn't belong",
    required super.prompt,
    super.asked,
    required this.sentences,
    required this.answer,
    required this.why,
  });

  final List<String> sentences;

  /// Index of the sentence that doesn't belong.
  final int answer;
  final String why;

  @override
  DrillKind get kind => DrillKind.oddOneOut;
}

/// A sentence with one gap ([before] + gap + [after]) and a bank of word tiles.
final class FillBlankExercise extends DrillExercise {
  const FillBlankExercise({
    required super.id,
    super.instruction = 'Fill in the blank',
    required super.prompt,
    super.asked,
    required this.before,
    required this.after,
    required this.bank,
    required this.answer,
    required this.why,
  });

  final String before;
  final String after;
  final List<String> bank;

  /// The tile that belongs in the gap; always one of [bank].
  final String answer;
  final String why;

  int get answerIndex => bank.indexOf(answer);

  @override
  DrillKind get kind => DrillKind.fillBlank;
}

/// Parts of a short answer to tap into the right order.
final class OrderExercise extends DrillExercise {
  const OrderExercise({
    required super.id,
    super.instruction = 'Tap the parts in order',
    required super.prompt,
    super.asked,
    required this.steps,
    required this.start,
    this.labels,
    required this.why,
  });

  /// The parts in the right order.
  final List<String> steps;

  /// The order the tiles first appear in, as indices into [steps]. Never the right order.
  final List<int> start;

  /// What each part does ("Situation", "Task"), shown once checked.
  final List<String>? labels;
  final String why;

  @override
  DrillKind get kind => DrillKind.order;
}

/// Writing practice: rewrite a vague [line] in your own words. There is no right answer; it is
/// accepted at [minWords] and then compared with [model].
final class RewriteExercise extends DrillExercise {
  const RewriteExercise({
    required super.id,
    super.instruction = 'Writing practice, not speaking',
    required super.prompt,
    super.asked,
    required this.line,
    required this.model,
    required this.tip,
    this.needsI = true,
  });

  static const minWords = 6;

  final String line;

  /// One way to say it, shown after checking.
  final String model;

  /// Shown when the rewrite already avoids the common slips.
  final String tip;

  /// The rewrite should say what the person did, with "I".
  final bool needsI;

  @override
  DrillKind get kind => DrillKind.rewrite;

  @override
  bool get scored => false;
}

/// How many words [text] has.
int drillWordCount(String text) => text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

final RegExp _self = RegExp(r"\b(i|me|my|im|ive)\b", caseSensitive: false);

const List<(String, String)> _fillers = [
  (r'\bum+\b', 'um'),
  (r'\buh+\b', 'uh'),
  (r'\bbasically\b', 'basically'),
  (r'\byou know\b', 'you know'),
  (r'\bkind of\b', 'kind of'),
  (r'\bsort of\b', 'sort of'),
  (r'\bi guess\b', 'I guess'),
  (r'(^|[,.]\s*)like,', 'like'),
];

/// The gentle note shown after a rewrite: the first common slip it still has, or the exercise's own
/// tip. Never a judgement; there is no wrong rewrite.
String rewriteTip(RewriteExercise exercise, String text) {
  if (exercise.needsI && !_self.hasMatch(text)) return 'Try saying what you did, with "I".';
  for (final (pattern, word) in _fillers) {
    if (RegExp(pattern, caseSensitive: false).hasMatch(text)) return 'Try it once more without "$word".';
  }
  return exercise.tip;
}

/// The skill whose lessons include [lessonId], or null.
DrillSkill? drillSkillFor(String lessonId, [List<DrillSkill> curriculum = drillCurriculum]) {
  for (final skill in curriculum) {
    if (skill.lessons.any((l) => l.id == lessonId)) return skill;
  }
  return null;
}

/// The lesson called [lessonId], or null.
DrillLesson? drillLessonById(String lessonId, [List<DrillSkill> curriculum = drillCurriculum]) {
  for (final skill in curriculum) {
    for (final lesson in skill.lessons) {
      if (lesson.id == lessonId) return lesson;
    }
  }
  return null;
}

/// The curriculum, in path order. Ids are stable: progress is saved against them.
const List<DrillSkill> drillCurriculum = [
  DrillSkill(
    id: 'intro',
    title: 'Introducing yourself',
    summary: 'A short, clear answer to "Tell me about yourself."',
    lessons: [
      DrillLesson(
        id: 'intro-1',
        title: 'Your opening',
        takeaway: "Say who you are now, one thing you've done, and why you're here. About a minute is plenty.",
        exercises: [
          ChoiceExercise(
            id: 'intro-1-a',
            prompt: 'Which opening gives the clearest picture of you?',
            asked: 'Tell me about yourself.',
            options: [
              "I was born in Ohio, and I've always liked meeting new people. I have two younger brothers and a dog.",
              "I'm a senior at Lincoln High. For two summers I've worked the front desk at our community pool, and "
                  "I'd like to keep working with people.",
              "I'm a hard worker, a fast learner and a real people person. I always give everything one hundred "
                  'percent.',
              "I'm not sure where to start, honestly. There's a lot I could say, so what would you like to know?",
            ],
            answer: 1,
            why: "It says who you are now, gives one real example, and says why you're here.",
          ),
          OddOneOutExercise(
            id: 'intro-1-b',
            prompt: 'One sentence in this answer is off topic.',
            asked: 'Tell me about yourself.',
            sentences: [
              "I'm finishing my first year of a business degree at Valley Community College.",
              'My favorite show right now is a baking competition.',
              'On weekends I tutor two middle school students in math.',
              "I'm applying because this role is a lot of explaining things clearly, which I enjoy.",
            ],
            answer: 1,
            why: "Your favorite show doesn't tell them how you'd do the job. The other sentences do.",
          ),
          FillBlankExercise(
            id: 'intro-1-c',
            prompt: 'Which verb says the most about your part?',
            before: 'Last fall I ',
            after: " the sign-up table for our school's food drive.",
            bank: ['saw', 'helped with', 'was around', 'ran'],
            answer: 'ran',
            why: '"Ran" says you were in charge. If that\'s true, say it. "Helped with" leaves them guessing.',
          ),
          OrderExercise(
            id: 'intro-1-d',
            prompt: 'Build a short answer that ends on why you want the job.',
            asked: 'Tell me about yourself.',
            steps: [
              "I'm a junior studying graphic design.",
              'This year I made posters and flyers for three school clubs.',
              'It taught me to work to a deadline and take feedback.',
              "That's why this design assistant role stood out to me.",
            ],
            start: [2, 0, 3, 1],
            labels: ['Who you are now', "What you've done", 'What you learned', 'Why this job'],
            why: "Now, then what you've done, then why you're here. It's easy to follow and ends on the job.",
          ),
          ChoiceExercise(
            id: 'intro-1-e',
            prompt: 'About how long should this answer be in a first interview?',
            asked: 'Tell me about yourself.',
            options: [
              'About 10 seconds: your name and your school',
              'About a minute: a few short sentences',
              'About five minutes: your story from the start',
              'As long as it takes to list everything',
            ],
            answer: 1,
            why: 'A minute is enough for a clear picture, and it leaves time for their questions.',
          ),
          RewriteExercise(
            id: 'intro-1-f',
            prompt: 'Rewrite this line so it says something real about you.',
            line: "I'm just a student, so I don't really have any experience.",
            model: "I'm a high school senior. Every Saturday this year I've volunteered at the library, helping kids "
                'find books.',
            tip: 'School, volunteering and projects count as experience. Naming one is enough.',
          ),
        ],
      ),
      DrillLesson(
        id: 'intro-2',
        title: 'Make it fit the job',
        takeaway: 'Choose the parts of your story that match what this job needs, and give one real reason you want '
            'it.',
        exercises: [
          ChoiceExercise(
            id: 'intro-2-a',
            prompt: "You're applying to be a cashier at a grocery store. Which detail is most useful to mention?",
            options: [
              'I made the honor roll in ninth grade.',
              'My family has shopped at this store for years.',
              "I like to stay busy, and I don't mind standing.",
              "At our band's bake sales, I ran the cash box and counted it at the end of each day.",
            ],
            answer: 3,
            why: "It shows you've already handled money carefully, which a cashier does all day.",
          ),
          OddOneOutExercise(
            id: 'intro-2-b',
            prompt: "You're applying to be a summer camp counselor. One sentence doesn't help this answer.",
            asked: 'Tell me about yourself.',
            sentences: [
              "For two seasons I've helped coach my little brother's soccer team.",
              "I'm certified in first aid and CPR.",
              'I like planning games that keep a big group involved.',
              "I'm hoping this job pays more than my last one.",
            ],
            answer: 3,
            why: "Pay is a fair question, but not here. This answer is about what you'd bring to the job.",
          ),
          FillBlankExercise(
            id: 'intro-2-c',
            prompt: 'Which reason sounds like you mean it?',
            before: "I'd like to work at your front desk because I enjoy ",
            after: '.',
            bank: ['working', 'stuff like that', 'helping people find what they need', 'everything about it'],
            answer: 'helping people find what they need',
            why: 'It names the part of the job you actually like, so it sounds true.',
          ),
          ChoiceExercise(
            id: 'intro-2-d',
            prompt: 'Which reply gives the best reason?',
            asked: 'Why do you want to work here?',
            options: [
              "I've shopped here for years, and the staff always take time to help. I'd like to do that too.",
              "Honestly, I need a job, and I saw your sign saying you're hiring right now.",
              'My friend works here, and she says the shifts are flexible and pretty easy.',
              "I'm open to pretty much anything right now, so this seemed like a good place to start.",
            ],
            answer: 0,
            why: "It gives a real reason and connects it to the work you'd do.",
          ),
          FillBlankExercise(
            id: 'intro-2-e',
            prompt: 'Which word links what you did to this job?',
            before: "I've worked the snack stand at basketball games, ",
            after: " I'm used to serving a long line quickly.",
            bank: ['so', 'but', 'although', 'unless'],
            answer: 'so',
            why: '"So" connects what you\'ve done to what this job needs.',
          ),
          RewriteExercise(
            id: 'intro-2-f',
            prompt: 'Rewrite this so it gives a real reason.',
            asked: 'Why do you want this job?',
            line: 'I want this job because it seems cool.',
            model: "I want this job because I like working with kids, and I've enjoyed helping at my school's "
                'after-school program.',
            tip: 'A real reason usually names a part of the work you like.',
          ),
        ],
      ),
    ],
  ),
  DrillSkill(
    id: 'example',
    title: 'Explaining an example',
    summary: 'A short story with your own part and how it turned out.',
    lessons: [
      DrillLesson(
        id: 'example-1',
        title: 'Say what you did',
        takeaway: 'Use "I" for your part, and name an action someone could picture.',
        exercises: [
          ChoiceExercise(
            id: 'example-1-a',
            prompt: 'Which sentence makes your part clearest?',
            options: [
              'We organized the whole fundraiser together as a team.',
              'The fundraiser got organized, and it went pretty well.',
              'I was part of the team that worked on the fundraiser.',
              'I set up the sign-up form and sent reminders to 40 volunteers.',
            ],
            answer: 3,
            why: 'It says what you did, with "I", and gives a number they can picture.',
          ),
          FillBlankExercise(
            id: 'example-1-b',
            prompt: 'It was your idea. Which word says so?',
            before: 'When our group fell behind, ',
            after: ' made a checklist so everyone knew their next task.',
            bank: ['we', 'they', 'I', 'someone'],
            answer: 'I',
            why: 'If you did it, say "I". They\'re getting to know you, not the group.',
          ),
          FillBlankExercise(
            id: 'example-1-c',
            prompt: 'Which verb shows a real action?',
            before: 'At the animal shelter, I ',
            after: " the dogs' feeding times on a shared whiteboard.",
            bank: ['dealt with', 'tracked', 'was involved in', 'did stuff with'],
            answer: 'tracked',
            why: '"Tracked" is an action they can picture. "Dealt with" could mean almost anything.',
          ),
          OddOneOutExercise(
            id: 'example-1-d',
            prompt: 'One sentence pulls attention away from your part.',
            asked: 'Tell me about a time you worked on a team.',
            sentences: [
              'Our class group had two weeks to build a website for a local bakery.',
              'I designed the menu page and tested it on three different phones.',
              'Group projects are usually unfair, because one person ends up doing everything.',
              'The owner still uses the menu page on her shop\'s site.',
            ],
            answer: 2,
            why: 'Complaining about group work takes the focus off what you did.',
          ),
          ChoiceExercise(
            id: 'example-1-e',
            prompt: 'A friend practicing with you says, "We organized everything." What should you ask them?',
            options: [
              'How many people were on the team?',
              'What did you do yourself?',
              'Was it fun to organize?',
              'Did it all go well in the end?',
            ],
            answer: 1,
            why: 'Their own part is what an interviewer wants to hear about.',
          ),
          RewriteExercise(
            id: 'example-1-f',
            prompt: 'Rewrite it so it says what you did.',
            line: 'We organized everything.',
            model: 'I made the schedule for 12 volunteers and texted everyone the day before.',
            tip: 'One thing you did and one detail they can picture is enough.',
          ),
        ],
      ),
      DrillLesson(
        id: 'example-2',
        title: 'End with a result',
        takeaway: 'Finish with what changed or what you learned. Small results count.',
        exercises: [
          OrderExercise(
            id: 'example-2-a',
            prompt: "Put this answer in an order that's easy to follow.",
            asked: 'Tell me about a problem you solved.',
            steps: [
              'Our robotics club kept missing meetings because no one knew the schedule.',
              'As club secretary, fixing that was my job.',
              'I set up a shared calendar and sent a reminder the night before each meeting.',
              'By the end of the term, almost everyone was showing up.',
            ],
            start: [3, 0, 2, 1],
            labels: ['Situation', 'Task', 'Action', 'Result'],
            why: 'Situation, task, action, result. They hear the problem before your fix, and the story ends on what '
                'changed.',
          ),
          ChoiceExercise(
            id: 'example-2-b',
            prompt: 'You reorganized the supply closet where you volunteer. Which ending gives a clear result?',
            options: [
              'After that, volunteers could find supplies in a minute instead of asking around.',
              'And that was pretty much it.',
              'It went well, I think, and people seemed happy.',
              'It took a lot of work, but I got through it.',
            ],
            answer: 0,
            why: 'It says what changed, so the story has a point.',
          ),
          FillBlankExercise(
            id: 'example-2-c',
            prompt: 'Which word turns this into a result?',
            before: 'After I made the new sign-up sheet, no one ',
            after: ' a shift for the rest of the semester.',
            bank: ['liked', 'thought about', 'missed', 'talked about'],
            answer: 'missed',
            why: '"Missed" makes it a result: the problem stopped.',
          ),
          ChoiceExercise(
            id: 'example-2-d',
            prompt: "Your example didn't work out the way you hoped. How should you end it?",
            options: [
              'Skip the ending and move on to something else.',
              "Say it failed, and explain it wasn't your fault.",
              "Say what you learned and what you'd do differently next time.",
              'Change the ending to a better result.',
            ],
            answer: 2,
            why: 'What you learned is a real ending, and it keeps the story honest.',
          ),
          OddOneOutExercise(
            id: 'example-2-e',
            prompt: "One sentence doesn't belong in this story.",
            asked: 'Tell me about a time you helped a customer.',
            sentences: [
              'A customer at the ice cream shop was upset that we were out of her favorite flavor.',
              'Our manager that summer was really strict about breaks.',
              'I offered her samples of two similar flavors.',
              'She picked one and came back the next week with her kids.',
            ],
            answer: 1,
            why: "The manager detail doesn't help the story about the customer.",
          ),
          RewriteExercise(
            id: 'example-2-f',
            prompt: 'You ran a recycling drive at school. Rewrite this ending so it gives a result.',
            line: 'It went well, I guess.',
            model: 'By the end of the month, the drive had collected over 300 cans, and the school kept the bins in '
                'every hallway.',
            tip: 'A result can be small: something that changed, or something you learned.',
            needsI: false,
          ),
        ],
      ),
    ],
  ),
  DrillSkill(
    id: 'followup',
    title: 'Answering a follow-up',
    summary: 'Answer the exact question first, then add one detail.',
    lessons: [
      DrillLesson(
        id: 'followup-1',
        title: 'Answer what they asked',
        takeaway: 'Answer the question in your first sentence. Then add one detail or reason.',
        exercises: [
          ChoiceExercise(
            id: 'followup-1-a',
            prompt: 'You mentioned leading a study group. Which reply answers their follow-up?',
            asked: 'How did you keep everyone on track?',
            options: [
              'Study groups are really helpful, especially before big tests.',
              'Everyone was pretty motivated, so it mostly worked out on its own.',
              "I've led a few other groups too, like a book club last year.",
              'I started each session with three topics, and we checked them off as we went.',
            ],
            answer: 3,
            why: 'It answers "how" right away, with one thing you actually did.',
          ),
          OddOneOutExercise(
            id: 'followup-1-b',
            prompt: "One sentence doesn't answer what they asked.",
            asked: 'What would you do differently next time?',
            sentences: [
              'The project was for my environmental science class.',
              "I'd ask for help sooner instead of trying to fix it alone.",
              "I'd also set a check-in halfway through the project.",
              "That way, small problems wouldn't pile up at the end.",
            ],
            answer: 0,
            why: 'They already know about the project. That sentence repeats background instead of answering.',
          ),
          FillBlankExercise(
            id: 'followup-1-c',
            prompt: 'Which answer is easiest to picture?',
            asked: 'How long did that take?',
            before: 'It took about ',
            after: ', mostly on weekends.',
            bank: ['a while', 'some time', 'forever', 'three weeks'],
            answer: 'three weeks',
            why: 'A real amount of time is easier to picture than "a while". Give your best honest estimate.',
          ),
          ChoiceExercise(
            id: 'followup-1-d',
            prompt: "They ask something you don't know the answer to. What's the best response?",
            options: [
              'Make up something that sounds right.',
              'Say "I don\'t know" and stop there.',
              "Say you're not sure, then share what you do know or how you'd find out.",
              'Change the subject to something you know well.',
            ],
            answer: 2,
            why: "Being honest and showing how you'd find out works better than guessing.",
          ),
          OrderExercise(
            id: 'followup-1-e',
            prompt: 'Put the reply in order so the answer comes first.',
            asked: 'How did you get the volunteers to reply faster?',
            steps: [
              'I moved our updates from email to a group chat.',
              'Most volunteers were students who checked their phones more than their email.',
              'After that, people replied within an hour instead of a day.',
            ],
            start: [2, 0, 1],
            labels: ['Answer', 'Reason', 'Result'],
            why: 'Answer first, then the reason, then what happened. They hear your answer right away.',
          ),
          RewriteExercise(
            id: 'followup-1-f',
            prompt: 'Rewrite this reply so it answers the question directly.',
            asked: 'What was the hardest part?',
            line: 'Honestly, all of it was kind of hard.',
            model: 'The hardest part was finding a date that worked for everyone. I fixed it by sending a quick poll '
                'with three options.',
            tip: 'Starting with the words of their question keeps you on track.',
            needsI: false,
          ),
        ],
      ),
      DrillLesson(
        id: 'followup-2',
        title: 'Add the missing detail',
        takeaway: 'When they ask for more, give one concrete detail, not a longer version of the same story.',
        exercises: [
          ChoiceExercise(
            id: 'followup-2-a',
            prompt: 'You said, "I helped at a food bank." Which reply gives them what they asked for?',
            asked: 'What did you do there?',
            options: [
              'I sorted donations by date and packed about 50 boxes each Saturday.',
              'Lots of different things, depending on the day.',
              'It was a really good experience, and I learned a lot.',
              'I went with a group from my church most weekends.',
            ],
            answer: 0,
            why: 'It names your actual tasks and gives a sense of how much you did.',
          ),
          FillBlankExercise(
            id: 'followup-2-b',
            prompt: 'Which word shows how you handled it?',
            asked: 'How did you handle the upset customer?',
            before: 'I ',
            after: ' to what she needed first, then offered to get my manager.',
            bank: ['reacted', 'went', 'listened', 'tried'],
            answer: 'listened',
            why: '"Listened" is an action they can picture, and it shows how you handled it.',
          ),
          OddOneOutExercise(
            id: 'followup-2-c',
            prompt: "One sentence doesn't fit what they asked.",
            asked: 'What did you learn from that job?',
            sentences: [
              'I learned to stay calm when the line got long.',
              "I also learned to ask a question when I wasn't sure.",
              'The store closed down two years later.',
              'Both of those help me at school now, too.',
            ],
            answer: 2,
            why: 'The store closing has nothing to do with what you learned.',
          ),
          ChoiceExercise(
            id: 'followup-2-d',
            prompt: "You said you're organized. Which reply gives a real example?",
            asked: 'Can you give me an example of that?',
            options: [
              "Sure. I've just always been a naturally organized person.",
              "I keep a planner with every assignment, and I haven't missed a deadline this semester.",
              "My friends always tell me I'm the most organized one.",
              'I could give you a lot of examples of that, honestly.',
            ],
            answer: 1,
            why: "An example is something you did. Saying the same thing in other words isn't one.",
          ),
          ChoiceExercise(
            id: 'followup-2-e',
            prompt: "You're not sure what they mean by a question. What can you say?",
            options: [
              'Answer something close and hope it fits.',
              '"That\'s a hard one. Can we skip it?"',
              '"Do you mean a challenge at school, or at work?"',
              'Say nothing and wait for them to explain.',
            ],
            answer: 2,
            why: 'A short clarifying question is normal, and it shows you want to answer well.',
          ),
          RewriteExercise(
            id: 'followup-2-f',
            prompt: "You mentioned helping at your aunt's bakery. Rewrite this reply so it gives a real detail.",
            asked: 'What did you do there?',
            line: 'I just helped out with stuff.',
            model: 'I worked the counter on Saturday mornings. I took orders, boxed pastries and kept the display case '
                'full.',
            tip: 'One or two specific tasks are enough.',
          ),
        ],
      ),
    ],
  ),
  DrillSkill(
    id: 'delivery',
    title: 'Clear delivery',
    summary: 'Short sentences, calm pauses and a clear ending.',
    lessons: [
      DrillLesson(
        id: 'delivery-1',
        title: 'Pauses, not fillers',
        takeaway: 'A short pause sounds calmer than "um". Short sentences give you places to pause.',
        exercises: [
          ChoiceExercise(
            id: 'delivery-1-a',
            prompt: 'Which version will be easiest to say clearly out loud?',
            options: [
              'So, um, basically I was like the person who, you know, ran the snack stand.',
              'Basically, I was kind of in charge of the snack stand, sort of.',
              'I was, like, the main snack stand person, I guess, basically.',
              "I ran the snack stand at our school's basketball games.",
            ],
            answer: 3,
            why: "It's short and direct, with no filler words to get through.",
          ),
          FillBlankExercise(
            id: 'delivery-1-b',
            prompt: 'You need a second to think. What helps?',
            before: 'Instead of saying "um", take a short ',
            after: '.',
            bank: ['pause', 'laugh', 'apology', 'guess'],
            answer: 'pause',
            why: 'A one-second pause gives you time to think, and it sounds calm to the listener.',
          ),
          OddOneOutExercise(
            id: 'delivery-1-c',
            prompt: 'One sentence weakens the end of this answer.',
            asked: 'Tell me about your last job.',
            sentences: [
              'I worked at the library help desk for a year.',
              'I helped students find books and use the printers.',
              'The busiest weeks were right before finals.',
              "So yeah, that's pretty much it, I guess.",
            ],
            answer: 3,
            why: 'Trailing off on filler weakens a good answer. Stop after your last real point.',
          ),
          ChoiceExercise(
            id: 'delivery-1-d',
            prompt: 'You lose your train of thought in the middle of an answer. What should you do?',
            options: [
              'Pause, and say, "Let me think for a second."',
              'Keep talking until it comes back to you.',
              'Apologize a few times and start over.',
              'Say "never mind" and stop.',
            ],
            answer: 0,
            why: 'A calm pause is normal. It gives you time without filling the silence.',
          ),
          ChoiceExercise(
            id: 'delivery-1-e',
            prompt: 'Which version would a listener follow most easily?',
            options: [
              'I worked at the pool and I also taught swim lessons and on weekends I worked the front desk and '
                  'sometimes the snack bar too.',
              'I worked at the pool. I taught swim lessons. On weekends, I ran the front desk.',
              'Pool, swim lessons, front desk, snack bar, weekends, a bit of everything really.',
            ],
            answer: 1,
            why: 'Short sentences give you natural places to pause and breathe.',
          ),
          RewriteExercise(
            id: 'delivery-1-f',
            prompt: 'Rewrite this without the filler words.',
            line: 'Um, so I basically, like, helped run the book fair, you know?',
            model: 'I helped run the book fair. I set up the tables and handled the cash box.',
            tip: 'Now read it out loud once, slowly.',
          ),
        ],
      ),
      DrillLesson(
        id: 'delivery-2',
        title: 'Sound sure, stay honest',
        takeaway: 'Drop the hedges. Say what you did plainly, and end on a clear point.',
        exercises: [
          ChoiceExercise(
            id: 'delivery-2-a',
            prompt: 'Which sounds sure of itself without overclaiming?',
            options: [
              'I think I maybe helped a little with the event, kind of.',
              'I single-handedly made our awards night a huge success.',
              "I planned the seating for our school's awards night.",
              'I guess I was sort of in charge of the seating?',
            ],
            answer: 2,
            why: "It says what you did plainly. It isn't too modest, and it isn't exaggerated.",
          ),
          FillBlankExercise(
            id: 'delivery-2-b',
            prompt: 'Which opening says something useful instead of hedging?',
            before: '',
            after: ' I set up a schedule so everyone knew their shift.',
            bank: ['I think maybe', 'Kind of,', 'Last spring,', 'Sort of,'],
            answer: 'Last spring,',
            why: 'A time detail helps them picture it. A hedge only makes you sound unsure.',
          ),
          OddOneOutExercise(
            id: 'delivery-2-c',
            prompt: 'One sentence plays down what you did.',
            asked: "Tell me about something you're proud of.",
            sentences: [
              'I trained three new volunteers at the animal shelter.',
              'I showed them how to check dogs in and out.',
              'But honestly, anyone could have done it.',
              'Two of them now help train new volunteers too.',
            ],
            answer: 2,
            why: 'Playing down your own work makes it harder for them to see what you did.',
          ),
          ChoiceExercise(
            id: 'delivery-2-d',
            prompt: 'Which last sentence ends the answer best?',
            options: [
              "So yeah, that's about it.",
              "Anyway, I don't know if that answers it.",
              'But that was a while ago now, so.',
              "That's why I'd like to do the same kind of work here.",
            ],
            answer: 3,
            why: "It ends on a clear point and links back to the job, so they know you're done.",
          ),
          ChoiceExercise(
            id: 'delivery-2-e',
            prompt: 'Your voice tends to fade at the end of sentences. What helps most?',
            options: [
              'Take a breath before your last sentence and say it as clearly as the first.',
              'Speak faster so the answer is over sooner.',
              'Add "you know" at the end to fill the gap.',
              'Look down at your notes as you finish.',
            ],
            answer: 0,
            why: 'Your last words are often the result. Keep them as clear as the start.',
          ),
          RewriteExercise(
            id: 'delivery-2-f',
            prompt: 'Rewrite this so it sounds sure and stays true.',
            line: "I'm not sure, but I think I was kind of good at helping customers?",
            model: "I'm good at helping customers. At the farmers market stand, regulars started asking for me by "
                'name.',
            tip: 'Back it up with one thing that happened.',
          ),
        ],
      ),
    ],
  ),
];
