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
        IF NEW.processing_state != 'pending' THEN
          IF EXISTS (
            SELECT 1
            FROM ethscriptions
            WHERE 
              (block_number < NEW.block_number AND processing_state = 'pending')
              OR 
              (block_number = NEW.block_number AND transaction_index < NEW.transaction_index AND processing_state = 'pending')
            LIMIT 1
          ) THEN
            RAISE EXCEPTION 'Previous ethscription with either a lower block number or a lower transaction index in the same block not yet processed';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;


--
-- Name: check_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      DECLARE
        call_status TEXT;
      BEGIN
        SELECT status INTO call_status FROM contract_calls WHERE transaction_hash = NEW.transaction_hash AND internal_transaction_index = 0;
        IF NEW.status <> call_status THEN
          RAISE EXCEPTION 'Receipt status must equal the status of the corresponding call';
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
-- Name: contract_artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_artifacts (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    block_number bigint NOT NULL,
    transaction_index bigint NOT NULL,
    name character varying NOT NULL,
    source_code text NOT NULL,
    init_code_hash character varying NOT NULL,
    "references" jsonb DEFAULT '[]'::jsonb NOT NULL,
    pragma_language character varying NOT NULL,
    pragma_version character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_e07e6a7a0d CHECK (((init_code_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
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
    call_type character varying NOT NULL,
    return_value jsonb,
    logs jsonb DEFAULT '[]'::jsonb NOT NULL,
    error jsonb,
    status character varying NOT NULL,
    block_number bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    block_blockhash character varying NOT NULL,
    transaction_index bigint NOT NULL,
    start_time timestamp(6) without time zone NOT NULL,
    end_time timestamp(6) without time zone NOT NULL,
    runtime_ms integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_0351aa702f CHECK (((created_contract_address IS NULL) OR ((created_contract_address)::text ~ '^0x[a-f0-9]{40}$'::text))),
    CONSTRAINT chk_rails_27a87dcd58 CHECK (((call_type)::text = ANY ((ARRAY['call'::character varying, 'create'::character varying])::text[]))),
    CONSTRAINT chk_rails_399807917b CHECK (((((status)::text = 'failure'::text) AND (logs = '[]'::jsonb)) OR ((status)::text = 'success'::text))),
    CONSTRAINT chk_rails_39b26367fa CHECK (((((status)::text = 'failure'::text) AND (error IS NOT NULL)) OR (((status)::text = 'success'::text) AND (error IS NULL)))),
    CONSTRAINT chk_rails_566710a5b9 CHECK (((((call_type)::text = 'create'::text) AND (error IS NULL)) OR (created_contract_address IS NULL))),
    CONSTRAINT chk_rails_60a50bca74 CHECK (((((call_type)::text = 'create'::text) AND ((effective_contract_address)::text = (created_contract_address)::text)) OR (((call_type)::text <> 'create'::text) AND ((effective_contract_address)::text = (to_contract_address)::text)))),
    CONSTRAINT chk_rails_634aef3d55 CHECK (((effective_contract_address IS NULL) OR ((effective_contract_address)::text ~ '^0x[a-f0-9]{40}$'::text))),
    CONSTRAINT chk_rails_b5e513ec63 CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_cebfc1a4ba CHECK (((to_contract_address IS NULL) OR ((to_contract_address)::text ~ '^0x[a-f0-9]{40}$'::text))),
    CONSTRAINT chk_rails_db6bb5ee1f CHECK (((status)::text = ANY ((ARRAY['success'::character varying, 'failure'::character varying])::text[]))),
    CONSTRAINT chk_rails_e0ca5e6f98 CHECK ((((call_type)::text <> 'create'::text) OR (error IS NOT NULL) OR (created_contract_address IS NOT NULL))),
    CONSTRAINT chk_rails_f785dc90f8 CHECK (((from_address)::text ~ '^0x[a-f0-9]{40}$'::text))
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
    contract_address character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_0db74a781b CHECK (((contract_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_2be3a94567 CHECK (((init_code_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_c9c6d246ab CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
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
    CONSTRAINT chk_rails_5494b20f4d CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_d696e6a11b CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text))
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
    block_number bigint NOT NULL,
    transaction_index bigint NOT NULL,
    current_type character varying NOT NULL,
    current_init_code_hash character varying NOT NULL,
    current_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    address character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_03af4f4a44 CHECK (((address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_afbe49f1ac CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_e1095f7a6a CHECK (((current_init_code_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
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
    processing_state character varying NOT NULL,
    transaction_count bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_11dbe1957f CHECK (((processing_state)::text = ANY ((ARRAY['no_ethscriptions'::character varying, 'pending'::character varying, 'complete'::character varying])::text[]))),
    CONSTRAINT chk_rails_1c105acdac CHECK (((parent_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_4f6ef583f4 CHECK ((((processing_state)::text <> 'complete'::text) OR (transaction_count IS NOT NULL))),
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
    transaction_hash character varying NOT NULL,
    block_number bigint NOT NULL,
    block_blockhash character varying NOT NULL,
    transaction_index bigint NOT NULL,
    creator character varying NOT NULL,
    initial_owner character varying NOT NULL,
    block_timestamp bigint NOT NULL,
    content_uri text NOT NULL,
    mimetype character varying NOT NULL,
    processed_at timestamp(6) without time zone,
    processing_state character varying NOT NULL,
    processing_error character varying,
    gas_price bigint,
    gas_used bigint,
    transaction_fee bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_13eacb6a26 CHECK ((((processing_state)::text = 'error'::text) OR (processing_error IS NULL))),
    CONSTRAINT chk_rails_3165541065 CHECK (((processing_state)::text = ANY ((ARRAY['pending'::character varying, 'success'::character varying, 'error'::character varying])::text[]))),
    CONSTRAINT chk_rails_7018b50304 CHECK ((((processing_state)::text = 'pending'::text) OR (processed_at IS NOT NULL))),
    CONSTRAINT chk_rails_788fa87594 CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_84591e2730 CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_b577b97822 CHECK (((creator)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_d807d90f03 CHECK ((((processing_state)::text <> 'error'::text) OR (processing_error IS NOT NULL))),
    CONSTRAINT chk_rails_df21fdbe02 CHECK (((initial_owner)::text ~ '^0x[a-f0-9]{40}$'::text))
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
-- Name: system_config_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_config_versions (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    block_number bigint NOT NULL,
    transaction_index bigint NOT NULL,
    supported_contracts jsonb DEFAULT '[]'::jsonb NOT NULL,
    start_block_number bigint,
    admin_address character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_31e7c0e109 CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_63a4680c0e CHECK (((admin_address)::text ~ '^0x[a-f0-9]{40}$'::text))
);


--
-- Name: system_config_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.system_config_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_config_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.system_config_versions_id_seq OWNED BY public.system_config_versions.id;


--
-- Name: transaction_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transaction_receipts (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    from_address character varying NOT NULL,
    status character varying NOT NULL,
    function character varying,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    logs jsonb DEFAULT '[]'::jsonb NOT NULL,
    block_timestamp bigint NOT NULL,
    error jsonb,
    effective_contract_address character varying,
    block_number bigint NOT NULL,
    transaction_index bigint NOT NULL,
    block_blockhash character varying NOT NULL,
    return_value jsonb,
    runtime_ms integer NOT NULL,
    call_type character varying NOT NULL,
    gas_price bigint,
    gas_used bigint,
    transaction_fee bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_06c0d4e0bb CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_8b922d101f CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_b5311d68b7 CHECK (((from_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_dab1f5e22a CHECK (((status)::text = ANY ((ARRAY['success'::character varying, 'failure'::character varying])::text[]))),
    CONSTRAINT chk_rails_e2780a945e CHECK (((effective_contract_address)::text ~ '^0x[a-f0-9]{40}$'::text))
);


--
-- Name: transaction_receipts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transaction_receipts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transaction_receipts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transaction_receipts_id_seq OWNED BY public.transaction_receipts.id;


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
-- Name: system_config_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_config_versions ALTER COLUMN id SET DEFAULT nextval('public.system_config_versions_id_seq'::regclass);


--
-- Name: transaction_receipts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_receipts ALTER COLUMN id SET DEFAULT nextval('public.transaction_receipts_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


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
-- Name: system_config_versions system_config_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_config_versions
    ADD CONSTRAINT system_config_versions_pkey PRIMARY KEY (id);


--
-- Name: transaction_receipts transaction_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_receipts
    ADD CONSTRAINT transaction_receipts_pkey PRIMARY KEY (id);


--
-- Name: idx_on_block_number_transaction_index_efc8dd9c1d; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_block_number_transaction_index_efc8dd9c1d ON public.system_config_versions USING btree (block_number, transaction_index);


--
-- Name: idx_on_block_number_txi_internal_txi; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_block_number_txi_internal_txi ON public.contract_calls USING btree (block_number, transaction_index, internal_transaction_index);


--
-- Name: idx_on_tx_hash_internal_txi; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_tx_hash_internal_txi ON public.contract_calls USING btree (transaction_hash, internal_transaction_index);


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
-- Name: index_contract_states_on_addr_block_number_tx_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_states_on_addr_block_number_tx_index ON public.contract_states USING btree (contract_address, block_number, transaction_index);


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
-- Name: index_contract_transactions_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_transactions_on_transaction_hash ON public.contract_transactions USING btree (transaction_hash);


--
-- Name: index_contract_tx_receipts_on_block_number_and_tx_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contract_tx_receipts_on_block_number_and_tx_index ON public.transaction_receipts USING btree (block_number, transaction_index);


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
-- Name: index_contracts_on_current_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_current_state ON public.contracts USING gin (current_state);


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
-- Name: index_ethscriptions_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ethscriptions_on_transaction_hash ON public.ethscriptions USING btree (transaction_hash);


--
-- Name: index_system_config_versions_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_system_config_versions_on_transaction_hash ON public.system_config_versions USING btree (transaction_hash);


--
-- Name: index_transaction_receipts_on_effective_contract_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transaction_receipts_on_effective_contract_address ON public.transaction_receipts USING btree (effective_contract_address);


--
-- Name: index_transaction_receipts_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_transaction_receipts_on_transaction_hash ON public.transaction_receipts USING btree (transaction_hash);


--
-- Name: eth_blocks check_block_sequence_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_block_sequence_trigger BEFORE UPDATE OF processing_state ON public.eth_blocks FOR EACH ROW EXECUTE FUNCTION public.check_block_sequence();


--
-- Name: ethscriptions check_ethscription_sequence_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_ethscription_sequence_trigger BEFORE UPDATE OF processing_state ON public.ethscriptions FOR EACH ROW EXECUTE FUNCTION public.check_ethscription_sequence();


--
-- Name: transaction_receipts check_status_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_status_trigger BEFORE INSERT OR UPDATE OF status ON public.transaction_receipts FOR EACH ROW EXECUTE FUNCTION public.check_status();


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
-- Name: contracts fk_rails_087f9c0a68; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_rails_087f9c0a68 FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: ethscriptions fk_rails_104cee2b3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions
    ADD CONSTRAINT fk_rails_104cee2b3d FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: transaction_receipts fk_rails_54b606737e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_receipts
    ADD CONSTRAINT fk_rails_54b606737e FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: contract_states fk_rails_54fdb5b7e7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_states
    ADD CONSTRAINT fk_rails_54fdb5b7e7 FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: contract_artifacts fk_rails_6aff674b66; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_artifacts
    ADD CONSTRAINT fk_rails_6aff674b66 FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: system_config_versions fk_rails_71887ba27f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_config_versions
    ADD CONSTRAINT fk_rails_71887ba27f FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: contract_calls fk_rails_84969f6044; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_calls
    ADD CONSTRAINT fk_rails_84969f6044 FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: contract_transactions fk_rails_a3a2f6ff66; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_transactions
    ADD CONSTRAINT fk_rails_a3a2f6ff66 FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: system_config_versions fk_rails_a7468c93b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_config_versions
    ADD CONSTRAINT fk_rails_a7468c93b0 FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: contract_transactions fk_rails_aa55c33b67; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_transactions
    ADD CONSTRAINT fk_rails_aa55c33b67 FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: contracts fk_rails_caa9d9df8b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_rails_caa9d9df8b FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: contract_artifacts fk_rails_de6793fa43; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_artifacts
    ADD CONSTRAINT fk_rails_de6793fa43 FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: transaction_receipts fk_rails_e9589fbc7a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_receipts
    ADD CONSTRAINT fk_rails_e9589fbc7a FOREIGN KEY (transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: contract_states fk_rails_ea304e7236; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_states
    ADD CONSTRAINT fk_rails_ea304e7236 FOREIGN KEY (contract_address) REFERENCES public.contracts(address) ON DELETE CASCADE;


--
-- Name: contract_states fk_rails_f5ab73470e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_states
    ADD CONSTRAINT fk_rails_f5ab73470e FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: contract_calls fk_rails_f9994c7a07; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_calls
    ADD CONSTRAINT fk_rails_f9994c7a07 FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20231113223006'),
('20231110173854'),
('20230911150931'),
('20230911143056'),
('20230824174647'),
('20230824171752'),
('20230824170608'),
('20230824165302'),
('20230824165301');

