{{ config(
    schema = 'balancer_v1_ethereum',
    tags = ['dunesql'],
    alias = alias('trades'),
    partition_by = ['block_month'],
    materialized = 'incremental',
    file_format = 'delta',
    incremental_strategy = 'merge',
    unique_key = ['block_time', 'tx_hash', 'evt_index']
    )
}}

{% set project_start_date = '2020-03-13' %}


WITH v1 AS (
    select
        '1' AS version,
        tokenOut AS token_bought_address,
        tokenAmountOut AS token_bought_amount_raw,
        tokenIn AS token_sold_address,
        tokenAmountIn AS token_sold_amount_raw,
        contract_address AS project_contract_address,
        evt_block_time,
        evt_tx_hash,
        evt_index
    from {{ source('balancer_v1_ethereum', 'BPool_evt_LOG_SWAP') }}
    {% if not is_incremental() %}
        where evt_block_time >= TIMESTAMP '{{project_start_date}}'
    {% endif %}
    {% if is_incremental() %}
        where evt_block_time >= date_trunc('day', now() - interval '7' day)
    {% endif %}
),
prices AS (
    select * from {{ source('prices', 'usd') }}
    where blockchain = 'ethereum'
    {% if not is_incremental() %}
        and minute >= TIMESTAMP '{{project_start_date}}'
    {% endif %}
    {% if is_incremental() %}
        and minute >= date_trunc('day', now() - interval '7' day)
    {% endif %}
)


select
    'ethereum' AS blockchain,
    'balancer' AS project,
    version,
    evt_block_time AS block_time,
    CAST(date_trunc('month', evt_block_time) AS DATE) AS block_month,
    TRY_CAST(date_trunc('day', evt_block_time) AS DATE) AS block_date,
    erc20a.symbol AS token_bought_symbol,
    erc20b.symbol AS token_sold_symbol,
    case
        when lower(erc20a.symbol) > lower(erc20b.symbol) then concat(erc20b.symbol, '-', erc20a.symbol)
        else concat(erc20a.symbol, '-', erc20b.symbol)
    end AS token_pair,
    token_bought_amount_raw / power(10, erc20a.decimals) AS token_bought_amount,
    token_sold_amount_raw / power(10, erc20b.decimals) AS token_sold_amount,
    CAST(token_bought_amount_raw AS UINT256) AS token_bought_amount_raw,
    CAST(token_sold_amount_raw AS UINT256) AS token_sold_amount_raw,
    coalesce(
        (token_bought_amount_raw / power(10, p_bought.decimals)) * p_bought.price,
        (token_sold_amount_raw / power(10, p_sold.decimals)) * p_sold.price
    ) AS amount_usd,
    token_bought_address,
    token_sold_address,
    tx."from" AS taker,
    CAST(NULL AS VARBINARY) AS maker,
    CAST(NULL AS VARBINARY) AS pool_id,
    CAST(NULL AS DOUBLE) AS swap_fee,
    project_contract_address,
    evt_tx_hash AS tx_hash,
    tx."from" AS tx_from,
    tx.to AS tx_to,
    evt_index
FROM v1 trades
INNER JOIN {{ source('ethereum', 'transactions') }} tx
    ON trades.evt_tx_hash = tx.hash
    {% if not is_incremental() %}
    AND tx.block_time >= TIMESTAMP '{{project_start_date}}'
    {% endif %}
    {% if is_incremental() %}
    AND tx.block_time >= date_trunc('day', now() - interval '7' day)
    {% endif %}
LEFT JOIN {{ ref('tokens_erc20') }} erc20a
    ON trades.token_bought_address = erc20a.contract_address
    AND erc20a.blockchain = 'ethereum'
LEFT JOIN {{ ref('tokens_erc20') }} erc20b
    ON trades.token_sold_address = erc20b.contract_address
    AND erc20b.blockchain = 'ethereum'
LEFT JOIN prices p_bought
    ON p_bought.minute = date_trunc('minute', trades.evt_block_time)
    AND p_bought.contract_address = trades.token_bought_address
LEFT JOIN prices p_sold
    ON p_sold.minute = date_trunc('minute', trades.evt_block_time)
    AND p_sold.contract_address = trades.token_sold_address
