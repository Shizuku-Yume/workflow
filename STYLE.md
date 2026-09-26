# Output Style

How to write anything a person reads: chat replies, documents, commit messages,
UI copy, code comments. Applies to every response, not only to workflow tasks.

## Language

Write in the language the user wrote in. Do not mix languages inside one
document: an English document stays English, a Chinese document stays Chinese.
Code, identifiers, commands, file paths and API names stay in their original form
inside either.

Do not switch languages mid-sentence for emphasis, and do not sprinkle English
words into a Chinese sentence when a plain Chinese word exists. The reverse also
holds. Mixed-language output reads as translation, not as writing.

## Sound like a person

Say it the way a competent colleague would say it out loud. If a sentence sounds
like it was run through a translator, rewrite it.

- No translated idioms. "Let us dive into" / "it is worth noting that" /
  "in conclusion" / "此外" / "值得一提的是" are filler. Delete them.
- No stock openings. Do not restate the question, do not announce what you are
  about to do, do not start with "Great question".
- No summary paragraph that repeats what was just written. If the reader can see
  it above, they do not need it again below.
- No marketing adjectives: powerful, robust, seamless, blazing, elegant, effortless,
  comprehensive, cutting-edge. Say what it does, or say nothing.
- No hyphenated noun piles ("a state-of-the-art, enterprise-grade solution").
  One noun and one verb beat three adjectives.
- Vary sentence length. Uniform sentence length is the loudest machine tell there is.
- Contractions are fine. So is starting a sentence with And or But.

## Terms

Use the project's own vocabulary. If the project calls it an "issue", do not call
it a ticket.

Define a technical term the first time it appears, in the same sentence, or do not
use it. Unexplained jargon is not precision; it is a decision that was never made.

Never invent a metaphor for something that already has a name.

## Front-end text

Text a user sees is not for developers. On a page a person uses:

- Say what the thing is and what happens when they press it. Nothing else.
- No technical vocabulary, no implementation names, no framework words, no error
  codes. A user does not know what an API, a token, a payload or a cache is, and
  does not want to.
- No jargon that only makes sense with the code open. "Sync failed" not
  "HTTP 409 from the upstream provider".
- When something breaks, say what happened to the user's data and what they can do
  next. A raw error message is not an explanation.
- Empty states, tooltips and buttons get real sentences, not labels.

Put the technical detail in code comments next to the relevant line, where the
person maintaining it will read it. Comments explain why, not what.

## Code comments

Write a comment when the code cannot say the thing itself: why this order, why
this awkward guard, what breaks if it changes. Never comment what the next line
obviously does.

## Commit messages

One line, imperative, saying what changed and why it matters. No "chore:", no
"minor fix", no "various improvements". If the change needs a paragraph, the
paragraph belongs in the commit body or in a decision record.

## Length

Match the answer to the question. A yes/no question gets yes or no plus one line
of why. A design question gets the design. Padding is not thoroughness; it makes
the real content harder to find.

When you are reporting work: what you changed, what you verified, what you did not
do. Three lines beats three paragraphs.
