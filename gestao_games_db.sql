-- ============================================================
-- 1a Pratica SAEP - Sistema de Gestao e Agendamento de Torneios
-- SGBD: PostgreSQL
-- ============================================================

-- Recria o schema para permitir executar o arquivo mais de uma vez.
DROP SCHEMA IF EXISTS gestao_games CASCADE;
CREATE SCHEMA gestao_games;
SET search_path TO gestao_games;

-- ============================================================
-- DDL - TABELAS
-- ============================================================

CREATE TABLE jogadores (
    id_jogador INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nickname VARCHAR(40) NOT NULL UNIQUE,
    email VARCHAR(120) NOT NULL UNIQUE,
    senha VARCHAR(100) NOT NULL,
    status VARCHAR(10) NOT NULL DEFAULT 'ativo',
    CONSTRAINT ck_jogador_status
        CHECK (status IN ('ativo', 'inativo', 'banido'))
);

CREATE TABLE jogos (
    id_jogo INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(80) NOT NULL UNIQUE,
    categoria VARCHAR(50) NOT NULL
);

CREATE TABLE torneios (
    id_torneio INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL UNIQUE,
    data_inicio DATE NOT NULL,
    data_fim DATE NOT NULL,
    status VARCHAR(15) NOT NULL DEFAULT 'inscricoes',
    CONSTRAINT ck_torneio_datas CHECK (data_fim >= data_inicio),
    CONSTRAINT ck_torneio_status
        CHECK (status IN ('inscricoes', 'em_andamento', 'encerrado'))
);

CREATE TABLE partidas (
    id_partida INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    titulo VARCHAR(120) NOT NULL,
    id_jogador INTEGER NOT NULL,
    id_jogo INTEGER NOT NULL,
    id_torneio INTEGER NOT NULL,
    data_agendamento TIMESTAMP NOT NULL,
    data_criacao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(15) NOT NULL DEFAULT 'agendada',
    CONSTRAINT fk_partida_jogador
        FOREIGN KEY (id_jogador) REFERENCES jogadores(id_jogador),
    CONSTRAINT fk_partida_jogo
        FOREIGN KEY (id_jogo) REFERENCES jogos(id_jogo),
    CONSTRAINT fk_partida_torneio
        FOREIGN KEY (id_torneio) REFERENCES torneios(id_torneio),
    CONSTRAINT ck_partida_status
        CHECK (status IN ('agendada', 'em_andamento', 'concluida', 'cancelada'))
);

CREATE TABLE historico_partidas (
    id_historico INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_partida INTEGER NOT NULL,
    acao VARCHAR(200) NOT NULL,
    data_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_historico_partida
        FOREIGN KEY (id_partida) REFERENCES partidas(id_partida)
);

-- ============================================================
-- PL/pgSQL - VALIDACAO ANTES DA INSERCAO DA PARTIDA
-- Garante jogador ativo e define automaticamente data_criacao.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_validar_partida()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_status_jogador VARCHAR(10);
BEGIN
    SELECT status
      INTO v_status_jogador
      FROM jogadores
     WHERE id_jogador = NEW.id_jogador;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Jogador % nao encontrado.', NEW.id_jogador;
    END IF;

    IF v_status_jogador <> 'ativo' THEN
        RAISE EXCEPTION
            'A partida so pode ser vinculada a jogador ativo. Status atual: %.',
            v_status_jogador;
    END IF;

    NEW.data_criacao := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_partida
BEFORE INSERT ON partidas
FOR EACH ROW
EXECUTE FUNCTION fn_validar_partida();

-- ============================================================
-- PL/pgSQL - REGISTRO AUTOMATICO NO HISTORICO
-- Executado depois que a partida for inserida com sucesso.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_registrar_historico_partida()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO historico_partidas (id_partida, acao)
    VALUES (
        NEW.id_partida,
        'Partida cadastrada: ' || NEW.titulo
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_registrar_historico_partida
AFTER INSERT ON partidas
FOR EACH ROW
EXECUTE FUNCTION fn_registrar_historico_partida();

-- ============================================================
-- DML - MASSA DE DADOS (minimo de 3 registros por tabela)
-- ============================================================

INSERT INTO jogadores (nickname, email, senha, status) VALUES
('NinjaBR', 'ninjabr@email.com', 'senha123', 'ativo'),
('LunaFPS', 'lunafps@email.com', 'senha456', 'ativo'),
('ShadowX', 'shadowx@email.com', 'senha789', 'ativo'),
('PlayerBanido', 'banido@email.com', 'senha000', 'banido');

INSERT INTO jogos (nome, categoria) VALUES
('Valorant', 'FPS'),
('League of Legends', 'MOBA'),
('Rocket League', 'Esportes');

INSERT INTO torneios (nome, data_inicio, data_fim, status) VALUES
('Copa Arena FPS', CURRENT_DATE + 2, CURRENT_DATE + 5, 'inscricoes'),
('Desafio MOBA', CURRENT_DATE + 7, CURRENT_DATE + 10, 'inscricoes'),
('Rocket Cup', CURRENT_DATE + 12, CURRENT_DATE + 14, 'inscricoes');

INSERT INTO partidas
    (titulo, id_jogador, id_jogo, id_torneio, data_agendamento, status)
VALUES
('NinjaBR x Equipe Alpha', 1, 1, 1, CURRENT_TIMESTAMP + INTERVAL '2 days', 'agendada'),
('LunaFPS x Equipe Eclipse', 2, 2, 2, CURRENT_TIMESTAMP + INTERVAL '4 days', 'agendada'),
('ShadowX x Equipe Turbo', 3, 3, 3, CURRENT_TIMESTAMP + INTERVAL '6 days', 'agendada');

-- ============================================================
-- FUNCTION DE CONSULTA - BUSCA POR NICKNAME OU E-MAIL
-- Pesquisa parcial, sem diferenciar letras maiusculas/minusculas.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_buscar_jogadores(p_termo TEXT)
RETURNS TABLE (
    id_jogador INTEGER,
    nickname VARCHAR(40),
    email VARCHAR(120),
    status VARCHAR(10)
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT j.id_jogador, j.nickname, j.email, j.status
      FROM jogadores AS j
     WHERE j.nickname ILIKE '%' || COALESCE(p_termo, '') || '%'
        OR j.email ILIKE '%' || COALESCE(p_termo, '') || '%'
     ORDER BY j.nickname;
END;
$$;

-- ============================================================
-- VIEW - PAINEL PRINCIPAL
-- ============================================================

CREATE OR REPLACE VIEW vw_painel_principal AS
SELECT
    j.nickname,
    p.titulo AS titulo_partida,
    g.categoria AS modalidade,
    p.data_agendamento AS data_partida,
    p.status AS status_disputa
FROM partidas AS p
JOIN jogadores AS j ON j.id_jogador = p.id_jogador
JOIN jogos AS g ON g.id_jogo = p.id_jogo;

-- ============================================================
-- VIEW - CRONOGRAMA DE PARTIDAS
-- A ordenacao e da data mais proxima para a mais distante.
-- A consulta da view tambem pode aplicar ORDER BY ao seleciona-la.
-- ============================================================

CREATE OR REPLACE VIEW vw_cronograma_partidas AS
SELECT
    p.id_partida,
    p.titulo AS titulo_partida,
    p.data_agendamento,
    p.status AS status_partida,
    (p.data_agendamento::date - CURRENT_DATE) AS dias_restantes,
    j.nickname AS jogador_responsavel,
    g.nome AS jogo,
    t.nome AS torneio
FROM partidas AS p
JOIN jogadores AS j ON j.id_jogador = p.id_jogador
JOIN jogos AS g ON g.id_jogo = p.id_jogo
JOIN torneios AS t ON t.id_torneio = p.id_torneio
ORDER BY p.data_agendamento ASC;

-- ============================================================
-- CONSULTAS PARA TESTAR O SISTEMA
-- ============================================================

-- Painel principal:
-- SELECT * FROM vw_painel_principal;

-- Cronograma em ordem cronologica:
-- SELECT * FROM vw_cronograma_partidas ORDER BY data_agendamento ASC;

-- Buscar jogador por parte do nickname ou e-mail:
-- SELECT * FROM fn_buscar_jogadores('ninja');

-- Conferir o historico criado automaticamente:
-- SELECT * FROM historico_partidas ORDER BY data_registro;

-- Teste de validacao: deve gerar erro porque o jogador esta banido.
-- INSERT INTO partidas
--     (titulo, id_jogador, id_jogo, id_torneio, data_agendamento)
-- VALUES
--     ('Teste invalido', 4, 1, 1, CURRENT_TIMESTAMP + INTERVAL '1 day');

-- ============================================================
-- FIM DO SCRIPT
-- Observacao: senha foi mantida como texto simples conforme o
-- enunciado da atividade. Em sistemas reais, use hash seguro.
-- ============================================================
