# Public copy

## Repository description

Multi-agent engineering with cold review, artifact validation and resumable run state.

## Post

The Bureau gives software reviewers a separate context and an evidence packet that excludes the conversation that produced the work. Artifact hashes and bidirectional coverage checks expose stale, missing or unexpected review evidence; decisions and handoffs stay in files for later sessions. The packet self-test exercises these checks without calling a model, and the review tour states what they cannot establish: careful reading or a sound verdict. This is the internal engineering system we use at Novadiem, published for inspection, without self-serve support or an open-source license. Start with the checkpoint review tour: [Novadiem-Studio/bureau](https://github.com/Novadiem-Studio/bureau).
