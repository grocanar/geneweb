DROP TABLE IF EXISTS person_group;
DROP TABLE IF EXISTS groups;
DROP TABLE IF EXISTS person_event;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS names;
DROP TABLE IF EXISTS persons;
DROP TABLE IF EXISTS sources;
DROP TABLE IF EXISTS notes;
DROP TABLE IF EXISTS places;

CREATE TABLE places (
	pl_id	INTEGER UNSIGNED AUTO_INCREMENT PRIMARY KEY,
	place	VARCHAR(120) NOT NULL,
	unique (place)
);

CREATE TABLE notes (
	n_id	INTEGER UNSIGNED AUTO_INCREMENT PRIMARY KEY,
	note	TEXT
);

CREATE TABLE sources (
	s_id	INTEGER UNSIGNED AUTO_INCREMENT PRIMARY KEY,
	source	TEXT
);

CREATE TABLE persons (
	p_id	INTEGER UNSIGNED PRIMARY KEY,
	occ	TINYINT UNSIGNED NOT NULL,
	death	enum('NotDead','Dead','DeadYoung','DeadDontKnowWhen','DontKnowIfDead','OfCourseDead') NOT NULL,
	n_id	INTEGER UNSIGNED,
	s_id	INTEGER UNSIGNED,
	consang	FLOAT(10) DEFAULT -1, -- FIXME spécifique
	sex	enum('','M','F') NOT NULL DEFAULT '',
	access	enum(
		'IfTitles',
		'Public',
		'Private'
	) NOT NULL DEFAULT 'IfTitles',
	FOREIGN KEY (n_id) REFERENCES notes(n_id),
	FOREIGN KEY (s_id) REFERENCES sources(s_id)
);
-- ALTER TABLE persons AUTO_INCREMENT=0;

CREATE TABLE names (
	n_id	INTEGER UNSIGNED AUTO_INCREMENT PRIMARY KEY,
	p_id	INTEGER UNSIGNED NOT NULL,
	givn	VARCHAR(120) NOT NULL,
	surn	VARCHAR(120) NOT NULL,
	main	Enum('True','False') NOT NULL DEFAULT 'False', -- FIXME à retravailler
	FOREIGN KEY (p_id) REFERENCES persons(p_id)
);

CREATE TABLE events (
	e_id	INTEGER UNSIGNED AUTO_INCREMENT PRIMARY KEY,
	-- Type
	type	ENUM(
		-- From INDIVIDUAL_EVENT_STRUCTURE
		'BIRT',
		'CHR',
		'DEAT',
		'BURI',
		'CREM',
		'ADOP',
		'BAPM',
		'BARM',
		'BASM',
		'CHRA',
		'CONF',
		'FCOM',
		'NATU',
		'EMIG',
		'IMMI',
		'CENS',
		'PROB',
		'WILL',
		'GRAD',
		'RETI', 
		'EVEN',
		-- From INDIVIDUAL_ATTRIBUTE_STRUCTURE
		'CAST',
		'DSCR',
		'EDUC',
		'IDNO',
		'NATI',
		'NCHI',
		'NMR',
		'OCCU',
		'PROP',
		'RELI',
		'RESI',
		'TITL', -- FIXME implémentation spécifique dans GeneWeb
		'FACT',
		-- From FAMILY_EVENT_STRUCTURE
		'ANNU',
		'DIV',
		'DIVF',
		'ENGA',
		'MARB',
		'MARC',
		'MARR',
		'MARL',
		'MARS'
	) NOT NULL,
	t_name	VARCHAR(90),
	-- Date
	d_prec	enum(
		'',
		'ABT',
		'Maybe', -- FIXME à supprimer
		'CAL',
		'EST',
		'BEF',
		'AFT',
		'FROM',
		'TO'
	) NOT NULL DEFAULT '',
	d_cal	enum(
		'Gregorian',
		'Julian',     -- @#DJULIAN@
		'French',     -- @#DFRENCH R@
		'Hebrew'      -- @#DHEBREW@
	) NOT NULL DEFAULT 'Gregorian',
	dmy_d	TINYINT UNSIGNED NOT NULL DEFAULT 0,
	dmy_m	TINYINT UNSIGNED NOT NULL DEFAULT 0,
	dmy_y	SMALLINT NOT NULL DEFAULT 0,
	d_text	VARCHAR(35) NOT NULL DEFAULT '', -- FIXME deprecated
	-- Autres champs
        death_reason enum (
		'Killed',
		'Murdered',
		'Executed',
		'Disappeared',
		''
	) NOT NULL DEFAULT '',
	place	VARCHAR(120) NOT NULL DEFAULT '', -- Removed after migration
	pl_id	INTEGER UNSIGNED,
	n_id	INTEGER UNSIGNED,
	s_id	INTEGER UNSIGNED,
	FOREIGN KEY (pl_id) REFERENCES places(pl_id),
	FOREIGN KEY (n_id) REFERENCES notes(n_id),
	FOREIGN KEY (s_id) REFERENCES sources(s_id)
);

CREATE TABLE person_event (
	r_id	INTEGER UNSIGNED AUTO_INCREMENT PRIMARY KEY,
	e_id	INTEGER UNSIGNED NOT NULL,
	p_id	INTEGER UNSIGNED NOT NULL,
	role	ENUM (
		'Main',
		'Witness',
		'GodParent',
		'Parent',
		'Official'
	) NOT NULL,
	FOREIGN KEY (p_id) REFERENCES persons(p_id),
	FOREIGN KEY (e_id) REFERENCES events(e_id)
);

CREATE TABLE groups (
	g_id	INTEGER UNSIGNED AUTO_INCREMENT PRIMARY KEY,
	n_id	INTEGER UNSIGNED,
	s_id	INTEGER UNSIGNED,
	origin  VARCHAR(100) NOT NULL, -- FIXME spécifique
	FOREIGN KEY (n_id) REFERENCES notes(n_id),
	FOREIGN KEY (s_id) REFERENCES sources(s_id)
);

CREATE TABLE person_group (
	r_id	INTEGER UNSIGNED AUTO_INCREMENT PRIMARY KEY,
	g_id	INTEGER UNSIGNED NOT NULL,
	p_id	INTEGER UNSIGNED NOT NULL,
	role	ENUM (
		'Father',
		'Mother',
		'Child',
		'AdoptedChild',    -- FIXME not used -> person_event
		'RecognitedChild', -- FIXME not used -> person_event
		'CandidateChild',
		'FosterChild'      -- FIXME not used -> person_event
	) NOT NULL,
	FOREIGN KEY (g_id) REFERENCES groups(g_id),
	FOREIGN KEY (p_id) REFERENCES persons(p_id)
);
