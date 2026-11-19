# shared/

The one language-neutral definition used by both `bench/` (Python) and `app/` (Flutter): the engine-event schema, engine profiles, pipeline config, the VAD model and test fixtures.

Both sides load these files. Never copy their values into code: change the file, with a commit message that cites the reason.
