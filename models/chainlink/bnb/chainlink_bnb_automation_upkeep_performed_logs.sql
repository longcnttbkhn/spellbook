{{
  config(
    tags=['dunesql'],
    alias=alias('automation_upkeep_performed_logs'),
    materialized='view',
    post_hook='{{ expose_spells(\'["bnb"]\',
                                "project",
                                "chainlink",
                                \'["linkpool_jon"]\') }}'
  )
}}

SELECT
  'bnb' as blockchain,
  block_hash,
  contract_address,
  data,
  topic0,
  topic1,
  topic2,
  topic3,
  tx_hash,
  block_number,
  block_time,
  index,
  tx_index,
  tx_from
FROM
  {{ source('bnb', 'logs') }} logs
WHERE
  topic0 = 0xcaacad83e47cc45c280d487ec84184eee2fa3b54ebaa393bda7549f13da228f6 -- UpkeepPerformed