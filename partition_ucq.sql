CREATE SCHEMA IF NOT EXISTS user_completed;

CREATE TABLE user_completed.questions (
  id BIGINT NOT NULL
  , "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
  , "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
  , "questionId" INT NOT NULL REFERENCES questions(id) ON DELETE CASCADE ON UPDATE CASCADE
  , "userId" INT NOT NULL REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE
  , correct BOOLEAN NOT NULL
  , PRIMARY KEY ("userId", "questionId")
) PARTITION BY RANGE ("userId");

CREATE INDEX ON user_completed.questions ("userId");

CREATE TABLE partman.template_user_completed_questions (
  LIKE user_completed.questions INCLUDING DEFAULTS
  , CONSTRAINT template_user_completed_questions_questionid_fk FOREIGN KEY ("questionId") REFERENCES questions(id) ON DELETE CASCADE ON UPDATE CASCADE
  , CONSTRAINT template_user_completed_questions_userid_fk FOREIGN KEY ("userId") REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE
  , PRIMARY KEY ("userId", "questionId")
);

SELECT partman.create_parent(
  p_parent_table := 'user_completed.questions'
  , p_control := 'userId'
  , p_interval := '10000'
  , p_template_table := 'partman.template_user_completed_questions'
);

ALTER TABLE user_completed_questions SET SCHEMA user_completed;

CALL partman.partition_data_proc(
  p_parent_table := 'user_completed.questions'
  , p_loop_count := 55
  , p_interval := '1000'
  , p_source_table := 'user_completed.user_completed_questions'
);

DROP TABLE user_completed.user_completed_questions CASCADE;

ALTER TABLE user_completed.questions DROP COLUMN id;

ALTER TABLE partman.template_user_completed_questions DROP COLUMN id;