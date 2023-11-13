SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: check_block_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_block_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF (SELECT MAX(block_number) FROM eth_blocks) IS NOT NULL AND (NEW.block_number <> (SELECT MAX(block_number) + 1 FROM eth_blocks) OR NEW.parent_blockhash <> (SELECT blockhash FROM eth_blocks WHERE block_number = NEW.block_number - 1)) THEN
          RAISE EXCEPTION 'New block number must be equal to max block number + 1, or this must be the first block';
        END IF;
        RETURN NEW;
      END;
      $$;


--
-- Name: check_block_sequence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_block_sequence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF NEW.processing_state = 'complete' THEN
          IF EXISTS (
            SELECT 1
            FROM eth_blocks
            WHERE block_number < NEW.block_number
              AND processing_state = 'pending'
            LIMIT 1
          ) THEN
            RAISE EXCEPTION 'Previous block not yet processed';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;


--
-- Name: check_ethscription_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_ethscription_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF NEW.block_number < (SELECT MAX(block_number) FROM ethscriptions) OR (NEW.block_number = (SELECT MAX(block_number) FROM ethscriptions) AND NEW.transaction_index <= (SELECT MAX(transaction_index) FROM ethscriptions WHERE block_number = NEW.block_number)) THEN
          RAISE EXCEPTION 'New ethscription must be later in order';
        END IF;
        RETURN NEW;
      END;
      $$;


--
-- Name: check_ethscription_sequence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_ethscription_sequence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF NEW.contract_actions_processed_at IS NOT NULL THEN
          IF EXISTS (
            SELECT 1
            FROM ethscriptions
            WHERE 
              (block_number < NEW.block_number AND contract_actions_processed_at IS NULL)
              OR 
              (block_number = NEW.block_number AND transaction_index < NEW.transaction_index AND contract_actions_processed_at IS NULL)
            LIMIT 1
          ) THEN
            RAISE EXCEPTION 'Previous ethscription with either a lower block number or a lower transaction index in the same block not yet processed';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;


--
-- Name: delete_later_blocks(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_later_blocks() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        DELETE FROM eth_blocks WHERE block_number > OLD.block_number;
        RETURN OLD;
      END;
      $$;


--
-- Name: delete_later_ethscriptions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_later_ethscriptions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        DELETE FROM ethscriptions WHERE block_number > OLD.block_number OR (block_number = OLD.block_number AND transaction_index > OLD.transaction_index);
        RETURN OLD;
      END;
      $$;


--
-- Name: update_current_state(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_current_state() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      DECLARE
        latest_contract_state RECORD;
      BEGIN
        IF TG_OP = 'INSERT' THEN
          SELECT INTO latest_contract_state *
          FROM contract_states
          WHERE contract_address = NEW.contract_address
          ORDER BY block_number DESC, transaction_index DESC
          LIMIT 1;

          UPDATE contracts
          SET current_state = latest_contract_state.state,
              current_type = latest_contract_state.type,
              current_init_code_hash = latest_contract_state.init_code_hash
          WHERE address = NEW.contract_address;
        ELSIF TG_OP = 'DELETE' THEN
          SELECT INTO latest_contract_state *
          FROM contract_states
          WHERE contract_address = OLD.contract_address
            AND id != OLD.id
          ORDER BY block_number DESC, transaction_index DESC
          LIMIT 1;

          UPDATE contracts
          SET current_state = latest_contract_state.state,
              current_type = latest_contract_state.type,
              current_init_code_hash = latest_contract_state.init_code_hash
          WHERE address = OLD.contract_address;
        END IF;
      
        RETURN NULL; -- result is ignored since this is an AFTER trigger
      END;
      $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: contract_allow_list_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_allow_list_versions (
    id bigint NOT NULL,
    ethscription_id character varying NOT NULL,
    block_number bigint NOT NULL,
    transaction_index bigint NOT NULL,
    allow_list jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: contract_allow_list_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_allow_list_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_allow_list_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_allow_list_versions_id_seq OWNED BY public.contract_allow_list_versions.id;


--
-- Name: contract_artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_artifacts (
    id bigint NOT NULL,
    name character varying NOT NULL,
    source_code text NOT NULL,
    ast text NOT NULL,
    init_code_hash character varying NOT NULL,
    "references" jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_97d3d8e44e CHECK (((init_code_hash)::text ~ '^[a-f0-9]{64}$'::text))
);


--
-- Name: contract_artifacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_artifacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_artifacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_artifacts_id_seq OWNED BY public.contract_artifacts.id;


--
-- Name: contract_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_calls (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    internal_transaction_index bigint NOT NULL,
    from_address character varying NOT NULL,
    to_contract_address character varying,
    created_contract_address character varying,
    effective_contract_address character varying,
    function character varying,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    call_type integer NOT NULL,
    return_value jsonb,
    logs jsonb DEFAULT '[]'::jsonb NOT NULL,
    error character varying,
    status integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT call_type_2_error_or_created_contract_address CHECK (((call_type <> 2) OR (error IS NOT NULL) OR (created_contract_address IS NOT NULL))),
    CONSTRAINT call_type_2_error_or_created_contract_address2 CHECK ((((call_type = 2) AND (error IS NULL)) OR (created_contract_address IS NULL))),
    CONSTRAINT created_contract_address_format CHECK (((created_contract_address IS NULL) OR ((created_contract_address)::text ~ '^0x[a-f0-9]{40}$'::text))),
    CONSTRAINT effective_contract_address_correct CHECK ((((call_type = 2) AND ((effective_contract_address)::text = (created_contract_address)::text)) OR ((call_type <> 2) AND ((effective_contract_address)::text = (to_contract_address)::text)))),
    CONSTRAINT from_address_format CHECK (((from_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT status_0_error_or_status_not_0_error CHECK ((((status = 0) AND (error IS NOT NULL)) OR ((status <> 0) AND (error IS NULL)))),
    CONSTRAINT status_0_logs_empty_or_status_not_0 CHECK ((((status = 0) AND (logs = '[]'::jsonb)) OR (status <> 0))),
    CONSTRAINT to_contract_address_format CHECK (((to_contract_address IS NULL) OR ((to_contract_address)::text ~ '^0x[a-f0-9]{40}$'::text))),
    CONSTRAINT transaction_hash_format CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: contract_calls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_calls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_calls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_calls_id_seq OWNED BY public.contract_calls.id;


--
-- Name: contract_states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_states (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    type character varying NOT NULL,
    init_code_hash character varying NOT NULL,
    state jsonb DEFAULT '{}'::jsonb NOT NULL,
    block_number bigint NOT NULL,
    transaction_index bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    contract_address character varying NOT NULL,
    CONSTRAINT chk_rails_05016dab2f CHECK (((init_code_hash)::text ~ '^[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_0d9a27b31a CHECK (((contract_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_e8714d0639 CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: contract_states_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_states_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_states_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_states_id_seq OWNED BY public.contract_states.id;


--
-- Name: contract_transaction_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_transaction_receipts (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    caller character varying NOT NULL,
    status integer NOT NULL,
    function_name character varying,
    function_args jsonb DEFAULT '{}'::jsonb NOT NULL,
    logs jsonb DEFAULT '[]'::jsonb NOT NULL,
    "timestamp" timestamp(6) without time zone NOT NULL,
    error_message character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    contract_address character varying,
    CONSTRAINT chk_rails_6a479b86d0 CHECK (((contract_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_bb3c17a6f6 CHECK (((caller)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_fac62f5815 CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: contract_transaction_receipts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_transaction_receipts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_transaction_receipts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_transaction_receipts_id_seq OWNED BY public.contract_transaction_receipts.id;


--
-- Name: contract_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_transactions (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    block_blockhash character varying NOT NULL,
    block_timestamp bigint NOT NULL,
    block_number bigint NOT NULL,
    transaction_index bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT block_blockhash_format CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT transaction_hash_format CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: contract_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_transactions_id_seq OWNED BY public.contract_transactions.id;


--
-- Name: contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    current_type character varying NOT NULL,
    current_init_code_hash character varying NOT NULL,
    current_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    address character varying NOT NULL,
    CONSTRAINT chk_rails_6d0039a684 CHECK (((address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_c653bcbc93 CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_cc2872e127 CHECK (((current_init_code_hash)::text ~ '^[a-f0-9]{64}$'::text))
);


--
-- Name: contracts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contracts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contracts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contracts_id_seq OWNED BY public.contracts.id;


--
-- Name: eth_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_blocks (
    id bigint NOT NULL,
    block_number bigint NOT NULL,
    "timestamp" bigint NOT NULL,
    blockhash character varying NOT NULL,
    parent_blockhash character varying NOT NULL,
    imported_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    processing_state character varying NOT NULL,
    CONSTRAINT chk_rails_1c105acdac CHECK (((parent_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_7e9881ece2 CHECK (((blockhash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: eth_blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.eth_blocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: eth_blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.eth_blocks_id_seq OWNED BY public.eth_blocks.id;


--
-- Name: ethscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ethscriptions (
    id bigint NOT NULL,
    ethscription_id character varying NOT NULL,
    block_number bigint NOT NULL,
    block_blockhash character varying NOT NULL,
    transaction_index bigint NOT NULL,
    creator character varying NOT NULL,
    initial_owner character varying NOT NULL,
    current_owner character varying NOT NULL,
    creation_timestamp bigint NOT NULL,
    previous_owner character varying,
    content_uri text NOT NULL,
    content_sha character varying NOT NULL,
    mimetype character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    contract_actions_processed_at timestamp(6) without time zone,
    CONSTRAINT ethscriptions_block_blockhash_format CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT ethscriptions_content_sha_format CHECK (((content_sha)::text ~ '^[a-f0-9]{64}$'::text)),
    CONSTRAINT ethscriptions_creator_format CHECK (((creator)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT ethscriptions_current_owner_format CHECK (((current_owner)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT ethscriptions_ethscription_id_format CHECK (((ethscription_id)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT ethscriptions_initial_owner_format CHECK (((initial_owner)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT ethscriptions_previous_owner_format CHECK (((previous_owner IS NULL) OR ((previous_owner)::text ~ '^0x[a-f0-9]{40}$'::text)))
);


--
-- Name: ethscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ethscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ethscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ethscriptions_id_seq OWNED BY public.ethscriptions.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: contract_allow_list_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_allow_list_versions ALTER COLUMN id SET DEFAULT nextval('public.contract_allow_list_versions_id_seq'::regclass);


--
-- Name: contract_artifacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_artifacts ALTER COLUMN id SET DEFAULT nextval('public.contract_artifacts_id_seq'::regclass);


--
-- Name: contract_calls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_calls ALTER COLUMN id SET DEFAULT nextval('public.contract_calls_id_seq'::regclass);


--
-- Name: contract_states id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_states ALTER COLUMN id SET DEFAULT nextval('public.contract_states_id_seq'::regclass);


--
-- Name: contract_transaction_receipts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_transaction_receipts ALTER COLUMN id SET DEFAULT nextval('public.contract_transaction_receipts_id_seq'::regclass);


--
-- Name: contract_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_transactions ALTER COLUMN id SET DEFAULT nextval('public.contract_transactions_id_seq'::regclass);


--
-- Name: contracts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts ALTER COLUMN id SET DEFAULT nextval('public.contracts_id_seq'::regclass);


--
-- Name: eth_blocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_blocks ALTER COLUMN id SET DEFAULT nextval('public.eth_blocks_id_seq'::regclass);


--
-- Name: ethscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions ALTER COLUMN id SET DEFAULT nextval('public.ethscriptions_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: contract_allow_list_versions contract_allow_list_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_allow_list_versions
    ADD CONSTRAINT contract_allow_list_versions_pkey PRIMARY KEY (id);


--
-- Name: contract_artifacts contract_artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_artifacts
    ADD CONSTRAINT contract_artifacts_pkey PRIMARY KEY (id);


--
-- Name: contract_calls contract_calls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_calls
    ADD CONSTRAINT contract_calls_pkey PRIMARY KEY (id);


--
-- Name: contract_states contract_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_states
    ADD CONSTRAINT contract_states_pkey PRIMARY KEY (id);


--
-- Name: contract_transaction_receipts contract_transaction_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_transaction_receipts
    ADD CONSTRAINT contract_transaction_receipts_pkey PRIMARY KEY (id);


--
-- Name: contract_transactions contract_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_transactions
    ADD CONSTRAINT contract_transactions_pkey PRIMARY KEY (id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (id);


--
-- Name: eth_blocks eth_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_blocks
    ADD CONSTRAINT eth_blocks_pkey PRIMARY KEY (id);


--
-- Name: ethscriptions ethscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions
    ADD CONSTRAINT ethscriptions_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: idx_on_block_number_transaction_index_e2ce48ceae; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_block_number_transaction_index_e2ce48ceae ON public.contract_allow_list_versions USING btree (block_number, transaction_index);


--
-- Name: index_contract_allow_list_versions_on_ethscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_allow_list_versions_on_ethscription_id ON public.contract_allow_list_versions USING btree (ethscription_id);


--
-- Name: index_contract_artifacts_on_init_code_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_artifacts_on_init_code_hash ON public.contract_artifacts USING btree (init_code_hash);


--
-- Name: index_contract_artifacts_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_artifacts_on_name ON public.contract_artifacts USING btree (name);


--
-- Name: index_contract_calls_on_call_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_calls_on_call_type ON public.contract_calls USING btree (call_type);


--
-- Name: index_contract_calls_on_contract_tx_id_and_internal_tx_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_calls_on_contract_tx_id_and_internal_tx_index ON public.contract_calls USING btree (transaction_hash, internal_transaction_index);


--
-- Name: index_contract_calls_on_created_contract_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_calls_on_created_contract_address ON public.contract_calls USING btree (created_contract_address);


--
-- Name: index_contract_calls_on_effective_contract_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_calls_on_effective_contract_address ON public.contract_calls USING btree (effective_contract_address);


--
-- Name: index_contract_calls_on_from_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_calls_on_from_address ON public.contract_calls USING btree (from_address);


--
-- Name: index_contract_calls_on_internal_transaction_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_calls_on_internal_transaction_index ON public.contract_calls USING btree (internal_transaction_index);


--
-- Name: index_contract_calls_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_calls_on_status ON public.contract_calls USING btree (status);


--
-- Name: index_contract_calls_on_to_contract_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_calls_on_to_contract_address ON public.contract_calls USING btree (to_contract_address);


--
-- Name: index_contract_states_on_contract_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_states_on_contract_address ON public.contract_states USING btree (contract_address);


--
-- Name: index_contract_states_on_contract_address_and_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_states_on_contract_address_and_transaction_hash ON public.contract_states USING btree (contract_address, transaction_hash);


--
-- Name: index_contract_states_on_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_states_on_state ON public.contract_states USING gin (state);


--
-- Name: index_contract_states_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_states_on_transaction_hash ON public.contract_states USING btree (transaction_hash);


--
-- Name: index_contract_transaction_receipts_on_contract_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_transaction_receipts_on_contract_address ON public.contract_transaction_receipts USING btree (contract_address);


--
-- Name: index_contract_transaction_receipts_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_transaction_receipts_on_transaction_hash ON public.contract_transaction_receipts USING btree (transaction_hash);


--
-- Name: index_contract_transaction_receipts_on_tx_hash_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contract_transaction_receipts_on_tx_hash_and_created_at ON public.contract_transaction_receipts USING btree (transaction_hash, created_at);


--
-- Name: index_contract_transactions_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_transactions_on_transaction_hash ON public.contract_transactions USING btree (transaction_hash);


--
-- Name: index_contract_txs_on_block_number_and_tx_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_txs_on_block_number_and_tx_index ON public.contract_transactions USING btree (block_number, transaction_index);


--
-- Name: index_contracts_on_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contracts_on_address ON public.contracts USING btree (address);


--
-- Name: index_contracts_on_current_init_code_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_current_init_code_hash ON public.contracts USING btree (current_init_code_hash);


--
-- Name: index_contracts_on_current_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_current_type ON public.contracts USING btree (current_type);


--
-- Name: index_contracts_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_transaction_hash ON public.contracts USING btree (transaction_hash);


--
-- Name: index_eth_blocks_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_block_number ON public.eth_blocks USING btree (block_number);


--
-- Name: index_eth_blocks_on_block_number_completed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_block_number_completed ON public.eth_blocks USING btree (block_number) WHERE ((processing_state)::text = 'complete'::text);


--
-- Name: index_eth_blocks_on_block_number_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_block_number_pending ON public.eth_blocks USING btree (block_number) WHERE ((processing_state)::text = 'pending'::text);


--
-- Name: index_eth_blocks_on_blockhash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_blockhash ON public.eth_blocks USING btree (blockhash);


--
-- Name: index_eth_blocks_on_imported_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_imported_at ON public.eth_blocks USING btree (imported_at);


--
-- Name: index_eth_blocks_on_imported_at_and_processing_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_imported_at_and_processing_state ON public.eth_blocks USING btree (imported_at, processing_state);


--
-- Name: index_eth_blocks_on_parent_blockhash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_parent_blockhash ON public.eth_blocks USING btree (parent_blockhash);


--
-- Name: index_eth_blocks_on_processing_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_processing_state ON public.eth_blocks USING btree (processing_state);


--
-- Name: index_eth_blocks_on_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_timestamp ON public.eth_blocks USING btree ("timestamp");


--
-- Name: index_ethscriptions_on_block_number_and_transaction_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ethscriptions_on_block_number_and_transaction_index ON public.ethscriptions USING btree (block_number, transaction_index);


--
-- Name: index_ethscriptions_on_content_sha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_content_sha ON public.ethscriptions USING btree (content_sha);


--
-- Name: index_ethscriptions_on_ethscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ethscriptions_on_ethscription_id ON public.ethscriptions USING btree (ethscription_id);


--
-- Name: eth_blocks check_block_sequence_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_block_sequence_trigger BEFORE UPDATE OF processing_state ON public.eth_blocks FOR EACH ROW EXECUTE FUNCTION public.check_block_sequence();


--
-- Name: ethscriptions check_ethscription_sequence_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_ethscription_sequence_trigger BEFORE UPDATE OF contract_actions_processed_at ON public.ethscriptions FOR EACH ROW EXECUTE FUNCTION public.check_ethscription_sequence();


--
-- Name: eth_blocks trigger_check_block_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_block_order BEFORE INSERT ON public.eth_blocks FOR EACH ROW EXECUTE FUNCTION public.check_block_order();


--
-- Name: ethscriptions trigger_check_ethscription_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_ethscription_order BEFORE INSERT ON public.ethscriptions FOR EACH ROW EXECUTE FUNCTION public.check_ethscription_order();


--
-- Name: eth_blocks trigger_delete_later_blocks; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_delete_later_blocks AFTER DELETE ON public.eth_blocks FOR EACH ROW EXECUTE FUNCTION public.delete_later_blocks();


--
-- Name: ethscriptions trigger_delete_later_ethscriptions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_delete_later_ethscriptions AFTER DELETE ON public.ethscriptions FOR EACH ROW EXECUTE FUNCTION public.delete_later_ethscriptions();


--
-- Name: contract_states update_current_state; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_current_state AFTER INSERT OR DELETE ON public.contract_states FOR EACH ROW EXECUTE FUNCTION public.update_current_state();


--
-- Name: ethscriptions fk_rails_104cee2b3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions
    ADD CONSTRAINT fk_rails_104cee2b3d FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: contract_transaction_receipts fk_rails_3ffb1ac226; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_transaction_receipts
    ADD CONSTRAINT fk_rails_3ffb1ac226 FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(ethscription_id) ON DELETE CASCADE;


--
-- Name: contract_states fk_rails_54fdb5b7e7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_states
    ADD CONSTRAINT fk_rails_54fdb5b7e7 FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(ethscription_id) ON DELETE CASCADE;


--
-- Name: contract_allow_list_versions fk_rails_61e3ad3da6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_allow_list_versions
    ADD CONSTRAINT fk_rails_61e3ad3da6 FOREIGN KEY (ethscription_id) REFERENCES public.ethscriptions(ethscription_id) ON DELETE CASCADE;


--
-- Name: contract_calls fk_rails_84969f6044; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_calls
    ADD CONSTRAINT fk_rails_84969f6044 FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(ethscription_id) ON DELETE CASCADE;


--
-- Name: contract_transactions fk_rails_a3a2f6ff66; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_transactions
    ADD CONSTRAINT fk_rails_a3a2f6ff66 FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(ethscription_id) ON DELETE CASCADE;


--
-- Name: contracts fk_rails_caa9d9df8b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_rails_caa9d9df8b FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(ethscription_id) ON DELETE CASCADE;


--
-- Name: contract_states fk_rails_ea304e7236; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_states
    ADD CONSTRAINT fk_rails_ea304e7236 FOREIGN KEY (contract_address) REFERENCES public.contracts(address) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20231113223006'),
('20231113184826'),
('20231110173854'),
('20231102162109'),
('20231001152142'),
('20230928185853'),
('20230911151706'),
('20230911150931'),
('20230911143056'),
('20230908205257'),
('20230824174647'),
('20230824171752'),
('20230824170608'),
('20230824165302');

