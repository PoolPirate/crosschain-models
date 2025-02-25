{{ config(
    materialized = 'incremental',
    unique_key = "CONCAT_WS('-', address, tag_name, start_date)",
    incremental_strategy = 'delete+insert',
) }}
-- We do not want to full refresh this model until we have a historical tags code set up.
-- to full-refresh either include the variable allow_full_refresh: True to command or comment out below code
-- DO NOT FORMAT will break the full refresh code if formatted copy from below

-- {% if execute %}
--   {% if flags.FULL_REFRESH and var('allow_full_refresh', False) != True %}
--       {{ exceptions.raise_compiler_error("Full refresh is not allowed for this model unless the argument \"- -vars 'allow_full_refresh: True'\" is included in the dbt run command.") }}
--   {% endif %}
-- {% endif %}
{% if execute %}
  {% if flags.FULL_REFRESH and var('allow_full_refresh', False) != True %}
      {{ exceptions.raise_compiler_error("Full refresh is not allowed for this model unless the argument \"- -vars 'allow_full_refresh: True'\" is included in the dbt run command.") }}
  {% endif %}
{% endif %}

WITH current_totals AS (
    SELECT
        DISTINCT user_address,
        MAX(
            last_activity_block_timestamp :: DATE
        ) AS start_date,
        SUM(usd_value_now) AS wallet_value,
        CASE
            WHEN SUM(usd_value_now) >= 1000000000 THEN 'wallet billionaire'
            WHEN SUM(usd_value_now) >= 1000000
            AND SUM(usd_value_now) < 1000000000 THEN 'wallet millionaire'
            ELSE 'NONE'
        END AS wallet_flag,
        NTILE(100) over(
            ORDER BY
                wallet_value
        ) AS wallet_group
    FROM
        {{ source(
            'ethereum_core',
            'ez_current_balances'
        ) }}
    GROUP BY
        1
    HAVING
        SUM(usd_value_now) >= 0
),
new_wallet_oner AS (
    SELECT
        'ethereum' AS blockchain,
        'flipside' AS creator,
        A.user_address AS address,
        'wallet top 1%' AS tag_name,
        'wallet' AS tag_type,
        A.start_date,
        NULL AS end_date,
        CURRENT_TIMESTAMP AS tag_created_at
    FROM
        current_totals A
    WHERE
        A.wallet_group = 100

{% if is_incremental() %}
AND A.user_address NOT IN (
    SELECT
        DISTINCT address
    FROM
        {{ this }}
    WHERE
        tag_name = 'wallet top 1%'
)
{% endif %}
),
new_billionaires AS (
    SELECT
        'ethereum' AS blockchain,
        'flipside' AS creator,
        A.user_address AS address,
        'wallet billionaire' AS tag_name,
        'wallet' AS tag_type,
        A.start_date,
        NULL AS end_date,
        CURRENT_TIMESTAMP AS tag_created_at
    FROM
        current_totals A
    WHERE
        A.wallet_flag = 'wallet billionaire'

{% if is_incremental() %}
AND A.user_address NOT IN (
    SELECT
        DISTINCT address
    FROM
        {{ this }}
    WHERE
        tag_name = 'wallet billionaire'
)
{% endif %}
),
new_millionaires AS (
    SELECT
        'ethereum' AS blockchain,
        'flipside' AS creator,
        A.user_address AS address,
        'wallet millionaire' AS tag_name,
        'wallet' AS tag_type,
        A.start_date,
        NULL AS end_date,
        CURRENT_TIMESTAMP AS tag_created_at
    FROM
        current_totals A
    WHERE
        A.wallet_flag = 'wallet millionaire'

{% if is_incremental() %}
AND A.user_address NOT IN (
    SELECT
        DISTINCT address
    FROM
        {{ this }}
    WHERE
        tag_name = 'wallet millionaire'
)
{% endif %}
)

{% if is_incremental() %},
cap_wallet_oner AS (
    SELECT
        'ethereum' AS blockchain,
        'flipside' AS creator,
        address,
        'wallet top 1%' AS tag_name,
        'wallet' AS tag_type,
        start_date,
        DATE_TRUNC(
            'DAY',
            CURRENT_DATE
        ) :: DATE AS end_date,
        CURRENT_TIMESTAMP AS tag_created_at
    FROM
        (
            SELECT
                *
            FROM
                {{ this }}
            WHERE
                tag_name = 'wallet top 1%'
        )
    WHERE
        address NOT IN (
            SELECT
                DISTINCT user_address
            FROM
                current_totals
            WHERE
                wallet_group = 100
        )
),
cap_billionaires AS (
    SELECT
        'ethereum' AS blockchain,
        'flipside' AS creator,
        address,
        'wallet billionaire' AS tag_name,
        'wallet' AS tag_type,
        start_date,
        DATE_TRUNC(
            'DAY',
            CURRENT_DATE
        ) :: DATE AS end_date,
        CURRENT_TIMESTAMP AS tag_created_at
    FROM
        (
            SELECT
                *
            FROM
                {{ this }}
            WHERE
                tag_name = 'wallet billionaire'
        )
    WHERE
        address NOT IN (
            SELECT
                DISTINCT user_address
            FROM
                current_totals
            WHERE
                wallet_flag = 'wallet billionaire'
        )
),
cap_millionaires AS (
    SELECT
        'ethereum' AS blockchain,
        'flipside' AS creator,
        address,
        'wallet millionaire' AS tag_name,
        'wallet' AS tag_type,
        start_date,
        DATE_TRUNC(
            'DAY',
            CURRENT_DATE
        ) :: DATE AS end_date,
        CURRENT_TIMESTAMP AS tag_created_at
    FROM
        (
            SELECT
                *
            FROM
                {{ this }}
            WHERE
                tag_name = 'wallet millionaire'
        )
    WHERE
        address NOT IN (
            SELECT
                DISTINCT user_address
            FROM
                current_totals
            WHERE
                wallet_flag = 'wallet millionaire'
        )
)
{% endif %}
SELECT
    *
FROM
    new_wallet_oner
UNION
SELECT
    *
FROM
    new_billionaires
UNION
SELECT
    *
FROM
    new_millionaires

{% if is_incremental() %}
UNION
SELECT
    *
FROM
    cap_wallet_oner
UNION
SELECT
    *
FROM
    cap_billionaires
UNION
SELECT
    *
FROM
    cap_millionaires
{% endif %}
