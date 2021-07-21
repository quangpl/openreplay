BEGIN;

-- --- public.sql ---

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- --- accounts.sql ---

CREATE OR REPLACE FUNCTION generate_api_key(length integer) RETURNS text AS
$$
declare
    chars  text[]  := '{0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z}';
    result text    := '';
    i      integer := 0;
begin
    if length < 0 then
        raise exception 'Given length cannot be less than 0';
    end if;
    for i in 1..length
        loop
            result := result || chars[1 + random() * (array_length(chars, 1) - 1)];
        end loop;
    return result;
end;
$$ LANGUAGE plpgsql;


CREATE TABLE tenants
(
    tenant_id      integer generated BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id        text                        NOT NULL DEFAULT generate_api_key(20),
    name           text,
    api_key        text UNIQUE                          default generate_api_key(20) not null,
    created_at     timestamp without time zone NOT NULL DEFAULT (now() at time zone 'utc'),
    deleted_at     timestamp without time zone NULL     DEFAULT NULL,
    edition        varchar(3)                  NOT NULL,
    version_number text                        NOT NULL,
    license        text                        NULL,
    opt_out        bool                        NOT NULL DEFAULT FALSE,
    t_projects     integer                     NOT NULL DEFAULT 1,
    t_sessions     bigint                      NOT NULL DEFAULT 0,
    t_users        integer                     NOT NULL DEFAULT 1,
    t_integrations integer                     NOT NULL DEFAULT 0
);

CREATE TYPE user_role AS ENUM ('owner', 'admin', 'member');
CREATE TYPE user_origin AS ENUM ('saml');
CREATE TABLE users
(
    user_id       integer generated BY DEFAULT AS IDENTITY PRIMARY KEY,
    tenant_id     integer                     NOT NULL REFERENCES tenants (tenant_id) ON DELETE CASCADE,
    email         text                        NOT NULL UNIQUE,
    role          user_role                   NOT NULL DEFAULT 'member',
    name          text                        NOT NULL,
    created_at    timestamp without time zone NOT NULL default (now() at time zone 'utc'),
    deleted_at    timestamp without time zone NULL     DEFAULT NULL,
    appearance    jsonb                       NOT NULL default '{
      "role": "dev",
      "dashboard": {
        "cpu": true,
        "fps": false,        
        "avgCpu": true,
        "avgFps": true,
        "errors": true,
        "crashes": true,
        "overview": true,
        "sessions": true,
        "topMetrics": true,
        "callsErrors": true,
        "pageMetrics": true,
        "performance": true,
        "timeToRender": false,
        "userActivity": false,
        "avgFirstPaint": false,
        "countSessions": true,
        "errorsPerType": true,
        "slowestImages": true,
        "speedLocation": true,
        "slowestDomains": true,
        "avgPageLoadTime": true,
        "avgTillFirstBit": false,
        "avgTimeToRender": true,
        "avgVisitedPages": false,
        "avgImageLoadTime": true,
        "busiestTimeOfDay": true,
        "errorsPerDomains": true,
        "missingResources": true,
        "resourcesByParty": true,
        "sessionsFeedback": false,
        "slowestResources": true,
        "avgUsedJsHeapSize": true,
        "domainsErrors_4xx": true,
        "domainsErrors_5xx": true,
        "memoryConsumption": true,
        "pagesDomBuildtime": false,
        "pagesResponseTime": true,
        "avgRequestLoadTime": true,
        "avgSessionDuration": false,
        "sessionsPerBrowser": false,
        "applicationActivity": true,
        "sessionsFrustration": false,
        "avgPagesDomBuildtime": true,
        "avgPagesResponseTime": false,
        "avgTimeToInteractive": true,
        "resourcesCountByType": true,
        "resourcesLoadingTime": true,
        "avgDomContentLoadStart": true,
        "avgFirstContentfulPixel": false,
        "resourceTypeVsResponseEnd": true,
        "impactedSessionsByJsErrors": true,
        "impactedSessionsBySlowPages": true,
        "resourcesVsVisuallyComplete": true,
        "pagesResponseTimeDistribution": true
      },
      "sessionsLive": false,
      "sessionsDevtools": true
    }'::jsonb,
    api_key       text UNIQUE                          default generate_api_key(20) not null,
    jwt_iat       timestamp without time zone NULL     DEFAULT NULL,
    data          jsonb                       NOT NULL DEFAULT '{}'::jsonb,
    weekly_report boolean                     NOT NULL DEFAULT TRUE,
	origin 		  user_origin 				  NULL     DEFAULT NULL,
	
);


CREATE TABLE basic_authentication
(
    user_id            integer                     NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    password           text                                 DEFAULT NULL,
    generated_password boolean                     NOT NULL DEFAULT false,
    token              text                        NULL     DEFAULT NULL,
    token_requested_at timestamp without time zone NULL     DEFAULT NULL,
    changed_at         timestamp,
    UNIQUE (user_id)
);


CREATE TYPE oauth_provider AS ENUM ('jira', 'github');
CREATE TABLE oauth_authentication
(
    user_id          integer        NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    provider         oauth_provider NOT NULL,
    provider_user_id text           NOT NULL,
    token            text           NOT NULL,
    UNIQUE (user_id, provider)
);


-- --- projects.sql ---

CREATE TABLE projects
(
    project_id           integer generated BY DEFAULT AS IDENTITY PRIMARY KEY,
    project_key          varchar(20)                 NOT NULL UNIQUE DEFAULT generate_api_key(20),
    tenant_id            integer                     NOT NULL REFERENCES tenants (tenant_id) ON DELETE CASCADE,
    name                 text                        NOT NULL,
    active               boolean                     NOT NULL,
    sample_rate          smallint                    NOT NULL        DEFAULT 100 CHECK (sample_rate >= 0 AND sample_rate <= 100),
    created_at           timestamp without time zone NOT NULL        DEFAULT (now() at time zone 'utc'),
    deleted_at           timestamp without time zone NULL            DEFAULT NULL,
    max_session_duration integer                     NOT NULL        DEFAULT 7200000,
    metadata_1           text                                        DEFAULT NULL,
    metadata_2           text                                        DEFAULT NULL,
    metadata_3           text                                        DEFAULT NULL,
    metadata_4           text                                        DEFAULT NULL,
    metadata_5           text                                        DEFAULT NULL,
    metadata_6           text                                        DEFAULT NULL,
    metadata_7           text                                        DEFAULT NULL,
    metadata_8           text                                        DEFAULT NULL,
    metadata_9           text                                        DEFAULT NULL,
    metadata_10          text                                        DEFAULT NULL,
    gdpr                 jsonb                       NOT NULL        DEFAULT '{
      "maskEmails": true,
      "sampleRate": 33,
      "maskNumbers": false,
      "defaultInputMode": "plain"
    }'::jsonb -- ??????
);

CREATE INDEX ON public.projects (project_key);

CREATE OR REPLACE FUNCTION notify_project() RETURNS trigger AS
$$
BEGIN
    PERFORM pg_notify('project', row_to_json(NEW)::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_insert_or_update
    AFTER INSERT OR UPDATE
    ON projects
    FOR EACH ROW
EXECUTE PROCEDURE notify_project();

-- --- alerts.sql ---

CREATE TYPE alert_detection_method AS ENUM ('threshold', 'change');

CREATE TABLE alerts
(
    alert_id         integer generated BY DEFAULT AS IDENTITY PRIMARY KEY,
    project_id       integer                NOT NULL REFERENCES projects (project_id) ON DELETE CASCADE,
    name             text                   NOT NULL,
    description      text                   NULL     DEFAULT NULL,
    active           boolean                NOT NULL DEFAULT TRUE,
    detection_method alert_detection_method NOT NULL,
    query            jsonb                  NOT NULL,
    deleted_at       timestamp              NULL     DEFAULT NULL,
    created_at       timestamp              NOT NULL DEFAULT timezone('utc'::text, now()),
    options          jsonb                  NOT NULL DEFAULT '{
      "renotifyInterval": 1440
    }'::jsonb
);


CREATE OR REPLACE FUNCTION notify_alert() RETURNS trigger AS
$$
DECLARE
    clone     jsonb;
    tenant_id integer;
BEGIN
    clone = to_jsonb(NEW);
    clone = jsonb_set(clone, '{created_at}', to_jsonb(CAST(EXTRACT(epoch FROM NEW.created_at) * 1000 AS BIGINT)));
    IF NEW.deleted_at NOTNULL THEN
        clone = jsonb_set(clone, '{deleted_at}', to_jsonb(CAST(EXTRACT(epoch FROM NEW.deleted_at) * 1000 AS BIGINT)));
    END IF;
    SELECT projects.tenant_id INTO tenant_id FROM public.projects WHERE projects.project_id = NEW.project_id LIMIT 1;
    clone = jsonb_set(clone, '{tenant_id}', to_jsonb(tenant_id));
    PERFORM pg_notify('alert', clone::text);
    RETURN NEW;
END ;
$$ LANGUAGE plpgsql;


CREATE TRIGGER on_insert_or_update_or_delete
    AFTER INSERT OR UPDATE OR DELETE
    ON alerts
    FOR EACH ROW
EXECUTE PROCEDURE notify_alert();


-- --- webhooks.sql ---

create type webhook_type as enum ('webhook', 'slack', 'email');

create table webhooks
(
    webhook_id  integer generated by default as identity
        constraint webhooks_pkey
            primary key,
    tenant_id   integer                                        not null
        constraint webhooks_tenant_id_fkey
            references tenants
            on delete cascade,
    endpoint    text                                           not null,
    created_at  timestamp default timezone('utc'::text, now()) not null,
    deleted_at  timestamp,
    auth_header text,
    type        webhook_type                                   not null,
    index       integer   default 0                            not null,
    name        varchar(100)
);

-- --- notifications.sql ---


CREATE TABLE notifications
(
    notification_id integer generated BY DEFAULT AS IDENTITY PRIMARY KEY,
    tenant_id       integer REFERENCES tenants (tenant_id) ON DELETE CASCADE,
    user_id         integer REFERENCES users (user_id) ON DELETE CASCADE,
    title           text        NOT NULL,
    description     text        NOT NULL,
    button_text     varchar(80) NULL,
    button_url      text        NULL,
    image_url       text        NULL,
    created_at      timestamp   NOT NULL DEFAULT timezone('utc'::text, now()),
    options         jsonb       NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT notification_tenant_xor_user CHECK ( tenant_id NOTNULL AND user_id ISNULL OR
                                                    tenant_id ISNULL AND user_id NOTNULL )
);
CREATE INDEX notifications_user_id_index ON public.notifications (user_id);
CREATE INDEX notifications_tenant_id_index ON public.notifications (tenant_id);
CREATE INDEX notifications_created_at_index ON public.notifications (created_at DESC);
CREATE INDEX notifications_created_at_epoch_idx ON public.notifications (CAST(EXTRACT(EPOCH FROM created_at) * 1000 AS BIGINT) DESC);

CREATE TABLE user_viewed_notifications
(
    user_id         integer NOT NULL REFERENCES users (user_id) on delete cascade,
    notification_id integer NOT NULL REFERENCES notifications (notification_id) on delete cascade,
    constraint user_viewed_notifications_pkey primary key (user_id, notification_id)
);

-- --- funnels.sql ---

CREATE TABLE funnels
(
    funnel_id  integer generated BY DEFAULT AS IDENTITY PRIMARY KEY,
    project_id integer NOT NULL REFERENCES projects (project_id) ON DELETE CASCADE,
    user_id    integer NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    name       text    not null,
    filter     jsonb   not null,
    created_at timestamp        default timezone('utc'::text, now()) not null,
    deleted_at timestamp,
    is_public  boolean NOT NULL DEFAULT False
);

CREATE INDEX ON public.funnels (user_id, is_public);

-- --- announcements.sql ---

create type announcement_type as enum ('notification', 'alert');

create table announcements
(
    announcement_id serial                                                      not null
        constraint announcements_pk
            primary key,
    title           text                                                        not null,
    description     text                                                        not null,
    button_text     varchar(30),
    button_url      text,
    image_url       text,
    created_at      timestamp         default timezone('utc'::text, now())      not null,
    type            announcement_type default 'notification'::announcement_type not null
);

-- --- integrations.sql ---

CREATE TYPE integration_provider AS ENUM ('bugsnag', 'cloudwatch', 'datadog', 'newrelic', 'rollbar', 'sentry', 'stackdriver', 'sumologic', 'elasticsearch'); --, 'jira', 'github');
CREATE TABLE integrations
(
    project_id   integer              NOT NULL REFERENCES projects (project_id) ON DELETE CASCADE,
    provider     integration_provider NOT NULL,
    options      jsonb                NOT NULL,
    request_data jsonb                NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (project_id, provider)
);

CREATE OR REPLACE FUNCTION notify_integration() RETURNS trigger AS
$$
BEGIN
    IF NEW IS NULL THEN
        PERFORM pg_notify('integration', (row_to_json(OLD)::text || '{"options": null, "request_data": null}'::text));
    ELSIF (OLD IS NULL) OR (OLD.options <> NEW.options) THEN
        PERFORM pg_notify('integration', row_to_json(NEW)::text);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_insert_or_update_or_delete
    AFTER INSERT OR UPDATE OR DELETE
    ON integrations
    FOR EACH ROW
EXECUTE PROCEDURE notify_integration();


create table jira_cloud
(
    user_id  integer not null
        constraint jira_cloud_pk
            primary key
        constraint jira_cloud_users_fkey
            references users
            on delete cascade,
    username text    not null,
    token    text    not null,
    url      text
);


-- --- issues.sql ---

CREATE TYPE issue_type AS ENUM (
    'click_rage',
    'dead_click',
    'excessive_scrolling',
    'bad_request',
    'missing_resource',
    'memory',
    'cpu',
    'slow_resource',
    'slow_page_load',
    'crash',
    'ml_cpu',
    'ml_memory',
    'ml_dead_click',
    'ml_click_rage',
    'ml_mouse_thrashing',
    'ml_excessive_scrolling',
    'ml_slow_resources',
    'custom',
    'js_exception'
    );

CREATE TABLE issues
(
    issue_id       text       NOT NULL PRIMARY KEY,
    project_id     integer    NOT NULL REFERENCES projects (project_id) ON DELETE CASCADE,
    type           issue_type NOT NULL,
    context_string text       NOT NULL,
    context        jsonb DEFAULT NULL
);
CREATE INDEX ON issues (issue_id, type);
CREATE INDEX issues_context_string_gin_idx ON public.issues USING GIN (context_string gin_trgm_ops);

-- --- errors.sql ---

CREATE TYPE error_source AS ENUM ('js_exception', 'bugsnag', 'cloudwatch', 'datadog', 'newrelic', 'rollbar', 'sentry', 'stackdriver', 'sumologic');
CREATE TYPE error_status AS ENUM ('unresolved', 'resolved', 'ignored');
CREATE TABLE errors
(
    error_id             text         NOT NULL PRIMARY KEY,
    project_id           integer      NOT NULL REFERENCES projects (project_id) ON DELETE CASCADE,
    source               error_source NOT NULL,
    name                 text                  DEFAULT NULL,
    message              text         NOT NULL,
    payload              jsonb        NOT NULL,
    status               error_status NOT NULL DEFAULT 'unresolved',
    parent_error_id      text                  DEFAULT NULL REFERENCES errors (error_id) ON DELETE SET NULL,
    stacktrace           jsonb, --to save the stacktrace and not query S3 another time
    stacktrace_parsed_at timestamp
);
CREATE INDEX ON errors (project_id, source);
CREATE INDEX errors_message_gin_idx ON public.errors USING GIN (message gin_trgm_ops);
CREATE INDEX errors_name_gin_idx ON public.errors USING GIN (name gin_trgm_ops);
CREATE INDEX errors_project_id_idx ON public.errors (project_id);
CREATE INDEX errors_project_id_status_idx ON public.errors (project_id, status);

CREATE TABLE user_favorite_errors
(
    user_id  integer NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    error_id text    NOT NULL REFERENCES errors (error_id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, error_id)
);

CREATE TABLE user_viewed_errors
(
    user_id  integer NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    error_id text    NOT NULL REFERENCES errors (error_id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, error_id)
);
CREATE INDEX user_viewed_errors_user_id_idx ON public.user_viewed_errors (user_id);
CREATE INDEX user_viewed_errors_error_id_idx ON public.user_viewed_errors (error_id);


-- --- sessions.sql ---
CREATE TYPE device_type AS ENUM ('desktop', 'tablet', 'mobile', 'other');
CREATE TYPE country AS ENUM ('UN', 'RW', 'SO', 'YE', 'IQ', 'SA', 'IR', 'CY', 'TZ', 'SY', 'AM', 'KE', 'CD', 'DJ', 'UG', 'CF', 'SC', 'JO', 'LB', 'KW', 'OM', 'QA', 'BH', 'AE', 'IL', 'TR', 'ET', 'ER', 'EG', 'SD', 'GR', 'BI', 'EE', 'LV', 'AZ', 'LT', 'SJ', 'GE', 'MD', 'BY', 'FI', 'AX', 'UA', 'MK', 'HU', 'BG', 'AL', 'PL', 'RO', 'XK', 'ZW', 'ZM', 'KM', 'MW', 'LS', 'BW', 'MU', 'SZ', 'RE', 'ZA', 'YT', 'MZ', 'MG', 'AF', 'PK', 'BD', 'TM', 'TJ', 'LK', 'BT', 'IN', 'MV', 'IO', 'NP', 'MM', 'UZ', 'KZ', 'KG', 'TF', 'HM', 'CC', 'PW', 'VN', 'TH', 'ID', 'LA', 'TW', 'PH', 'MY', 'CN', 'HK', 'BN', 'MO', 'KH', 'KR', 'JP', 'KP', 'SG', 'CK', 'TL', 'RU', 'MN', 'AU', 'CX', 'MH', 'FM', 'PG', 'SB', 'TV', 'NR', 'VU', 'NC', 'NF', 'NZ', 'FJ', 'LY', 'CM', 'SN', 'CG', 'PT', 'LR', 'CI', 'GH', 'GQ', 'NG', 'BF', 'TG', 'GW', 'MR', 'BJ', 'GA', 'SL', 'ST', 'GI', 'GM', 'GN', 'TD', 'NE', 'ML', 'EH', 'TN', 'ES', 'MA', 'MT', 'DZ', 'FO', 'DK', 'IS', 'GB', 'CH', 'SE', 'NL', 'AT', 'BE', 'DE', 'LU', 'IE', 'MC', 'FR', 'AD', 'LI', 'JE', 'IM', 'GG', 'SK', 'CZ', 'NO', 'VA', 'SM', 'IT', 'SI', 'ME', 'HR', 'BA', 'AO', 'NA', 'SH', 'BV', 'BB', 'CV', 'GY', 'GF', 'SR', 'PM', 'GL', 'PY', 'UY', 'BR', 'FK', 'GS', 'JM', 'DO', 'CU', 'MQ', 'BS', 'BM', 'AI', 'TT', 'KN', 'DM', 'AG', 'LC', 'TC', 'AW', 'VG', 'VC', 'MS', 'MF', 'BL', 'GP', 'GD', 'KY', 'BZ', 'SV', 'GT', 'HN', 'NI', 'CR', 'VE', 'EC', 'CO', 'PA', 'HT', 'AR', 'CL', 'BO', 'PE', 'MX', 'PF', 'PN', 'KI', 'TK', 'TO', 'WF', 'WS', 'NU', 'MP', 'GU', 'PR', 'VI', 'UM', 'AS', 'CA', 'US', 'PS', 'RS', 'AQ', 'SX', 'CW', 'BQ', 'SS');
CREATE TYPE platform AS ENUM ('web','ios','android');

CREATE TABLE sessions
(
    session_id              bigint PRIMARY KEY,
    project_id              integer      NOT NULL REFERENCES projects (project_id) ON DELETE CASCADE,
    tracker_version         text         NOT NULL,
    start_ts                bigint       NOT NULL,
    duration                integer      NULL,
    rev_id                  text                  DEFAULT NULL,
    platform                platform     NOT NULL DEFAULT 'web',
    is_snippet              boolean      NOT NULL DEFAULT FALSE,
    user_id                 text                  DEFAULT NULL,
    user_anonymous_id       text                  DEFAULT NULL,
    user_uuid               uuid         NOT NULL,
    user_agent              text                  DEFAULT NULL,
    user_os                 text         NOT NULL,
    user_os_version         text                  DEFAULT NULL,
    user_browser            text                  DEFAULT NULL,
    user_browser_version    text                  DEFAULT NULL,
    user_device             text         NOT NULL,
    user_device_type        device_type  NOT NULL,
    user_device_memory_size integer               DEFAULT NULL,
    user_device_heap_size   bigint                DEFAULT NULL,
    user_country            country      NOT NULL,
    pages_count             integer      NOT NULL DEFAULT 0,
    events_count            integer      NOT NULL DEFAULT 0,
    errors_count            integer      NOT NULL DEFAULT 0,
    watchdogs_score         bigint       NOT NULL DEFAULT 0,
    issue_score             bigint       NOT NULL DEFAULT 0,
    issue_types             issue_type[] NOT NULL DEFAULT '{}'::issue_type[],
    metadata_1              text                  DEFAULT NULL,
    metadata_2              text                  DEFAULT NULL,
    metadata_3              text                  DEFAULT NULL,
    metadata_4              text                  DEFAULT NULL,
    metadata_5              text                  DEFAULT NULL,
    metadata_6              text                  DEFAULT NULL,
    metadata_7              text                  DEFAULT NULL,
    metadata_8              text                  DEFAULT NULL,
    metadata_9              text                  DEFAULT NULL,
    metadata_10             text                  DEFAULT NULL
--   ,
--   rehydration_id integer REFERENCES rehydrations(rehydration_id) ON DELETE SET NULL
);
CREATE INDEX ON sessions (project_id, start_ts);
CREATE INDEX ON sessions (project_id, user_id);
CREATE INDEX ON sessions (project_id, user_anonymous_id);
CREATE INDEX ON sessions (project_id, user_device);
CREATE INDEX ON sessions (project_id, user_country);
CREATE INDEX ON sessions (project_id, user_browser);
CREATE INDEX ON sessions (project_id, metadata_1);
CREATE INDEX ON sessions (project_id, metadata_2);
CREATE INDEX ON sessions (project_id, metadata_3);
CREATE INDEX ON sessions (project_id, metadata_4);
CREATE INDEX ON sessions (project_id, metadata_5);
CREATE INDEX ON sessions (project_id, metadata_6);
CREATE INDEX ON sessions (project_id, metadata_7);
CREATE INDEX ON sessions (project_id, metadata_8);
CREATE INDEX ON sessions (project_id, metadata_9);
CREATE INDEX ON sessions (project_id, metadata_10);
-- CREATE INDEX ON sessions (rehydration_id);
CREATE INDEX ON sessions (project_id, watchdogs_score DESC);
CREATE INDEX platform_idx ON public.sessions (platform);

CREATE INDEX sessions_metadata1_gin_idx ON public.sessions USING GIN (metadata_1 gin_trgm_ops);
CREATE INDEX sessions_metadata2_gin_idx ON public.sessions USING GIN (metadata_2 gin_trgm_ops);
CREATE INDEX sessions_metadata3_gin_idx ON public.sessions USING GIN (metadata_3 gin_trgm_ops);
CREATE INDEX sessions_metadata4_gin_idx ON public.sessions USING GIN (metadata_4 gin_trgm_ops);
CREATE INDEX sessions_metadata5_gin_idx ON public.sessions USING GIN (metadata_5 gin_trgm_ops);
CREATE INDEX sessions_metadata6_gin_idx ON public.sessions USING GIN (metadata_6 gin_trgm_ops);
CREATE INDEX sessions_metadata7_gin_idx ON public.sessions USING GIN (metadata_7 gin_trgm_ops);
CREATE INDEX sessions_metadata8_gin_idx ON public.sessions USING GIN (metadata_8 gin_trgm_ops);
CREATE INDEX sessions_metadata9_gin_idx ON public.sessions USING GIN (metadata_9 gin_trgm_ops);
CREATE INDEX sessions_metadata10_gin_idx ON public.sessions USING GIN (metadata_10 gin_trgm_ops);
CREATE INDEX sessions_user_os_gin_idx ON public.sessions USING GIN (user_os gin_trgm_ops);
CREATE INDEX sessions_user_browser_gin_idx ON public.sessions USING GIN (user_browser gin_trgm_ops);
CREATE INDEX sessions_user_device_gin_idx ON public.sessions USING GIN (user_device gin_trgm_ops);
CREATE INDEX sessions_user_id_gin_idx ON public.sessions USING GIN (user_id gin_trgm_ops);
CREATE INDEX sessions_user_anonymous_id_gin_idx ON public.sessions USING GIN (user_anonymous_id gin_trgm_ops);
CREATE INDEX sessions_user_country_gin_idx ON public.sessions (project_id, user_country);
CREATE INDEX ON sessions (project_id, user_country);
CREATE INDEX ON sessions (project_id, user_browser);
CREATE INDEX sessions_session_id_project_id_start_ts_durationNN_idx ON sessions (session_id, project_id, start_ts) WHERE duration IS NOT NULL;


ALTER TABLE public.sessions
    ADD CONSTRAINT web_browser_constraint CHECK ( (sessions.platform = 'web' AND sessions.user_browser NOTNULL) OR
                                                  (sessions.platform != 'web' AND sessions.user_browser ISNULL));

ALTER TABLE public.sessions
    ADD CONSTRAINT web_user_browser_version_constraint CHECK ( sessions.platform = 'web' OR sessions.user_browser_version ISNULL);

ALTER TABLE public.sessions
    ADD CONSTRAINT web_user_agent_constraint CHECK ( (sessions.platform = 'web' AND sessions.user_agent NOTNULL) OR
                                                     (sessions.platform != 'web' AND sessions.user_agent ISNULL));



CREATE TABLE user_viewed_sessions
(
    user_id    integer NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    session_id bigint  NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, session_id)
);

CREATE TABLE user_favorite_sessions
(
    user_id    integer NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    session_id bigint  NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, session_id)
);


-- --- assignments.sql ---

create table assigned_sessions
(
    session_id    bigint                                         NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    issue_id      text                                           NOT NULL,
    provider      oauth_provider                                 NOT NULL,
    created_by    integer                                        NOT NULL,
    created_at    timestamp default timezone('utc'::text, now()) NOT NULL,
    provider_data jsonb     default '{}'::jsonb                  NOT NULL
);
CREATE INDEX ON assigned_sessions(session_id);

-- --- events_common.sql ---

CREATE SCHEMA events_common;

CREATE TYPE events_common.custom_level AS ENUM ('info','error');

CREATE TABLE events_common.customs
(
    session_id bigint                     NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    timestamp  bigint                     NOT NULL,
    seq_index  integer                    NOT NULL,
    name       text                       NOT NULL,
    payload    jsonb                      NOT NULL,
    level      events_common.custom_level NOT NULL DEFAULT 'info',
    PRIMARY KEY (session_id, timestamp, seq_index)
);
CREATE INDEX ON events_common.customs (name);
CREATE INDEX customs_name_gin_idx ON events_common.customs USING GIN (name gin_trgm_ops);
CREATE INDEX ON events_common.customs (timestamp);


CREATE TABLE events_common.issues
(
    session_id bigint  NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    timestamp  bigint  NOT NULL,
    seq_index  integer NOT NULL,
    issue_id   text    NOT NULL REFERENCES issues (issue_id) ON DELETE CASCADE,
    payload    jsonb DEFAULT NULL,
    PRIMARY KEY (session_id, timestamp, seq_index)
);


CREATE TABLE events_common.requests
(
    session_id bigint  NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    timestamp  bigint  NOT NULL,
    seq_index  integer NOT NULL,
    url        text    NOT NULL,
    duration   integer NOT NULL,
    success    boolean NOT NULL,
    PRIMARY KEY (session_id, timestamp, seq_index)
);
CREATE INDEX ON events_common.requests (url);
CREATE INDEX ON events_common.requests (duration);
CREATE INDEX requests_url_gin_idx ON events_common.requests USING GIN (url gin_trgm_ops);
CREATE INDEX ON events_common.requests (timestamp);
CREATE INDEX requests_url_gin_idx2 ON events_common.requests USING GIN (RIGHT(url, length(url) - (CASE
                                                                                                      WHEN url LIKE 'http://%'
                                                                                                          THEN 7
                                                                                                      WHEN url LIKE 'https://%'
                                                                                                          THEN 8
                                                                                                      ELSE 0 END))
                                                                        gin_trgm_ops);

-- --- events.sql ---
CREATE SCHEMA events;

CREATE TABLE events.pages
(
    session_id                  bigint NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    message_id                  bigint NOT NULL,
    timestamp                   bigint NOT NULL,
    host                        text   NOT NULL,
    path                        text   NOT NULL,
    base_path                   text   NOT NULL,
    referrer                    text    DEFAULT NULL,
    base_referrer               text    DEFAULT NULL,
    dom_building_time           integer DEFAULT NULL,
    dom_content_loaded_time     integer DEFAULT NULL,
    load_time                   integer DEFAULT NULL,
    first_paint_time            integer DEFAULT NULL,
    first_contentful_paint_time integer DEFAULT NULL,
    speed_index                 integer DEFAULT NULL,
    visually_complete           integer DEFAULT NULL,
    time_to_interactive         integer DEFAULT NULL,
    response_time               bigint  DEFAULT NULL,
    response_end                bigint  DEFAULT NULL,
    ttfb                        integer DEFAULT NULL,
    PRIMARY KEY (session_id, message_id)
);
CREATE INDEX ON events.pages (session_id);
CREATE INDEX pages_base_path_gin_idx ON events.pages USING GIN (base_path gin_trgm_ops);
CREATE INDEX pages_base_referrer_gin_idx ON events.pages USING GIN (base_referrer gin_trgm_ops);
CREATE INDEX ON events.pages (timestamp);
CREATE INDEX pages_base_path_gin_idx2 ON events.pages USING GIN (RIGHT(base_path, length(base_path) - 1) gin_trgm_ops);
CREATE INDEX pages_base_path_idx ON events.pages (base_path);
CREATE INDEX pages_base_path_idx2 ON events.pages (RIGHT(base_path, length(base_path) - 1));
CREATE INDEX pages_base_referrer_idx ON events.pages (base_referrer);
CREATE INDEX pages_base_referrer_gin_idx2 ON events.pages USING GIN (RIGHT(base_referrer, length(base_referrer) - (CASE
                                                                                                                       WHEN base_referrer LIKE 'http://%'
                                                                                                                           THEN 7
                                                                                                                       WHEN base_referrer LIKE 'https://%'
                                                                                                                           THEN 8
                                                                                                                       ELSE 0 END))
                                                                     gin_trgm_ops);
CREATE INDEX ON events.pages (response_time);
CREATE INDEX ON events.pages (response_end);
CREATE INDEX pages_path_gin_idx ON events.pages USING GIN (path gin_trgm_ops);
CREATE INDEX pages_path_idx ON events.pages (path);
CREATE INDEX pages_visually_complete_idx ON events.pages (visually_complete) WHERE visually_complete > 0;
CREATE INDEX pages_dom_building_time_idx ON events.pages (dom_building_time) WHERE dom_building_time > 0;
CREATE INDEX pages_load_time_idx ON events.pages (load_time) WHERE load_time > 0;
CREATE INDEX pages_base_path_session_id_timestamp_idx ON events.pages (base_path,session_id,timestamp);


CREATE TABLE events.clicks
(
    session_id bigint NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    message_id bigint NOT NULL,
    timestamp  bigint NOT NULL,
    label      text DEFAULT NULL,
    PRIMARY KEY (session_id, message_id)
);
CREATE INDEX ON events.clicks (session_id);
CREATE INDEX ON events.clicks (label);
CREATE INDEX clicks_label_gin_idx ON events.clicks USING GIN (label gin_trgm_ops);
CREATE INDEX ON events.clicks (timestamp);
CREATE INDEX clicks_label_session_id_timestamp_idx ON events.clicks (label,session_id,timestamp);
CREATE INDEX clicks_url_idx ON events.clicks (url);
CREATE INDEX clicks_url_gin_idx ON events.clicks USING GIN (url gin_trgm_ops);
CREATE INDEX clicks_url_session_id_timestamp_selector_idx ON events.clicks (url, session_id, timestamp,selector);


CREATE TABLE events.inputs
(
    session_id bigint NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    message_id bigint NOT NULL,
    timestamp  bigint NOT NULL,
    label      text DEFAULT NULL,
    value      text DEFAULT NULL,
    PRIMARY KEY (session_id, message_id)
);
CREATE INDEX ON events.inputs (session_id);
CREATE INDEX ON events.inputs (label, value);
CREATE INDEX inputs_label_gin_idx ON events.inputs USING GIN (label gin_trgm_ops);
CREATE INDEX inputs_label_idx ON events.inputs (label);
CREATE INDEX ON events.inputs (timestamp);
CREATE INDEX inputs_label_session_id_timestamp_idx ON events.inputs (label,session_id,timestamp);

CREATE TABLE events.errors
(
    session_id bigint NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    message_id bigint NOT NULL,
    timestamp  bigint NOT NULL,
    error_id   text   NOT NULL REFERENCES errors (error_id) ON DELETE CASCADE,
    PRIMARY KEY (session_id, message_id)
);
CREATE INDEX ON events.errors (session_id);
CREATE INDEX ON events.errors (timestamp);


CREATE TABLE events.graphql
(
    session_id bigint NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    message_id bigint NOT NULL,
    timestamp  bigint NOT NULL,
    name       text   NOT NULL,
    PRIMARY KEY (session_id, message_id)
);
CREATE INDEX ON events.graphql (name);
CREATE INDEX graphql_name_gin_idx ON events.graphql USING GIN (name gin_trgm_ops);
CREATE INDEX ON events.graphql (timestamp);

CREATE TABLE events.state_actions
(
    session_id bigint NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    message_id bigint NOT NULL,
    timestamp  bigint NOT NULL,
    name       text   NOT NULL,
    PRIMARY KEY (session_id, message_id)
);
CREATE INDEX ON events.state_actions (name);
CREATE INDEX state_actions_name_gin_idx ON events.state_actions USING GIN (name gin_trgm_ops);
CREATE INDEX ON events.state_actions (timestamp);

CREATE TYPE events.resource_type AS ENUM ('other', 'script', 'stylesheet', 'fetch', 'img', 'media');
CREATE TYPE events.resource_method AS ENUM ('GET' , 'HEAD' , 'POST' , 'PUT' , 'DELETE' , 'CONNECT' , 'OPTIONS' , 'TRACE' , 'PATCH' );
CREATE TABLE events.resources
(
    session_id        bigint                 NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    message_id        bigint                 NOT NULL,
    timestamp         bigint                 NOT NULL,
    duration          bigint                 NULL,
    type              events.resource_type   NOT NULL,
    url               text                   NOT NULL,
    url_host          text                   NOT NULL,
    url_hostpath      text                   NOT NULL,
    success           boolean                NOT NULL,
    status            smallint               NULL,
    method            events.resource_method NULL,
    ttfb              bigint                 NULL,
    header_size       bigint                 NULL,
    encoded_body_size integer                NULL,
    decoded_body_size integer                NULL,
    PRIMARY KEY (session_id, message_id)
);
CREATE INDEX ON events.resources (session_id);
CREATE INDEX ON events.resources (timestamp);
CREATE INDEX ON events.resources (success);
CREATE INDEX ON events.resources (status);
CREATE INDEX ON events.resources (type);
CREATE INDEX ON events.resources (duration) WHERE duration > 0;
CREATE INDEX ON events.resources (url_host);

CREATE INDEX resources_url_gin_idx ON events.resources USING GIN (url gin_trgm_ops);
CREATE INDEX resources_url_idx ON events.resources (url);
CREATE INDEX resources_url_hostpath_gin_idx ON events.resources USING GIN (url_hostpath gin_trgm_ops);
CREATE INDEX resources_url_hostpath_idx ON events.resources (url_hostpath);



CREATE TABLE events.performance
(
    session_id             bigint   NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    timestamp              bigint   NOT NULL,
    message_id             bigint   NOT NULL,
    min_fps                smallint NOT NULL,
    avg_fps                smallint NOT NULL,
    max_fps                smallint NOT NULL,
    min_cpu                smallint NOT NULL,
    avg_cpu                smallint NOT NULL,
    max_cpu                smallint NOT NULL,
    min_total_js_heap_size bigint   NOT NULL,
    avg_total_js_heap_size bigint   NOT NULL,
    max_total_js_heap_size bigint   NOT NULL,
    min_used_js_heap_size  bigint   NOT NULL,
    avg_used_js_heap_size  bigint   NOT NULL,
    max_used_js_heap_size  bigint   NOT NULL,
    PRIMARY KEY (session_id, message_id)
);


CREATE OR REPLACE FUNCTION events.funnel(steps integer[], m integer) RETURNS boolean AS
$$
DECLARE
    step integer;
    c    integer := 0;
BEGIN
    FOREACH step IN ARRAY steps
        LOOP
            IF step + c = 0 THEN
                IF c = 0 THEN
                    RETURN false;
                END IF;
                c := 0;
                CONTINUE;
            END IF;
            IF c + 1 = step THEN
                c := step;
            END IF;
        END LOOP;
    RETURN c = m;
END;
$$ LANGUAGE plpgsql IMMUTABLE;


-- --- autocomplete.sql ---

CREATE TABLE autocomplete
(
    value      text    NOT NULL,
    type       text    NOT NULL,
    project_id integer NOT NULL REFERENCES projects (project_id) ON DELETE CASCADE
);

CREATE unique index autocomplete_unique ON autocomplete (project_id, value, type);
CREATE index autocomplete_project_id_idx ON autocomplete (project_id);
CREATE INDEX autocomplete_type_idx ON public.autocomplete (type);
CREATE INDEX autocomplete_value_gin_idx ON public.autocomplete USING GIN (value gin_trgm_ops);

-- --- jobs.sql ---
CREATE TYPE job_status AS ENUM ('scheduled','running','cancelled','failed','completed');
CREATE TYPE job_action AS ENUM ('delete_user_data');
CREATE TABLE jobs
(
    job_id       integer generated BY DEFAULT AS IDENTITY PRIMARY KEY,
    description  text                                           NOT NULL,
    status       job_status                                     NOT NULL,
    project_id   integer                                        NOT NULL REFERENCES projects (project_id) ON DELETE CASCADE,
    action       job_action                                     NOT NULL,
    reference_id text                                           NOT NULL,
    created_at   timestamp default timezone('utc'::text, now()) NOT NULL,
    updated_at   timestamp default timezone('utc'::text, now()) NULL,
    start_at     timestamp                                      NOT NULL,
    errors       text                                           NULL
);
CREATE INDEX ON jobs (status);
CREATE INDEX ON jobs (start_at);

COMMIT;
