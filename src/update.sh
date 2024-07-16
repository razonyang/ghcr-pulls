#!/bin/bash
# Scrape each package
# Usage: ./update.sh
# Copyright (c) ipitio
#
# shellcheck disable=SC1091,SC2015

source lib.sh

main() {
    set_up
    TODAY=$(get_BKG BKG_TODAY)
    # remove owners from queue that have already been scraped in this batch
    echo "Updating environment"
    [ -n "$BKG_BATCH_FIRST_STARTED" ] || set_BKG BKG_BATCH_FIRST_STARTED "$TODAY"
    BKG_BATCH_FIRST_STARTED=$(get_BKG BKG_BATCH_FIRST_STARTED)
    set_BKG BKG_TIMEOUT "2"
    [ -n "$(get_BKG BKG_OWNERS_QUEUE)" ] && [ "$1" = "0" ] && get_BKG BKG_OWNERS_QUEUE | perl -pe 's/\\n/\n/g' | env_parallel --lb remove_owner || :
    [ -n "$(get_BKG BKG_OWNERS_QUEUE)" ] || set_BKG BKG_BATCH_FIRST_STARTED "$TODAY"
    BKG_BATCH_FIRST_STARTED=$(get_BKG BKG_BATCH_FIRST_STARTED)
    [ -n "$(get_BKG BKG_RATE_LIMIT_START)" ] || set_BKG BKG_RATE_LIMIT_START "$(date -u +%s)"
    [ -n "$(get_BKG BKG_CALLS_TO_API)" ] || set_BKG BKG_CALLS_TO_API "0"

    # reset the rate limit if an hour has passed since the last run started
    if (($(get_BKG BKG_RATE_LIMIT_START) + 3600 <= $(date -u +%s))); then
        set_BKG BKG_RATE_LIMIT_START "$(date -u +%s)"
        set_BKG BKG_CALLS_TO_API "0"
    fi

    # reset the secondary rate limit if a minute has passed since the last run started
    if (($(get_BKG BKG_MIN_RATE_LIMIT_START) + 60 <= $(date -u +%s))); then
        set_BKG BKG_MIN_RATE_LIMIT_START "$(date -u +%s)"
        set_BKG BKG_MIN_CALLS_TO_API "0"
    fi

    echo "Updated environment"

    # if this is a scheduled update, scrape all owners that haven't been scraped in this batch
    if [ "$1" = "0" ]; then
        # get more owners if no more
        if [ -z "$(get_BKG BKG_OWNERS_QUEUE)" ]; then
            echo "Finding more owners..."
            [ -n "$(get_BKG BKG_LAST_SCANNED_ID)" ] || set_BKG BKG_LAST_SCANNED_ID "0"
            seq 1 10 | env_parallel --lb page_owner
            echo "Found more owners"
        fi

        # add the owners in the database to the owners array
        echo "Reading known owners..."
        query="select owner_id, owner from '$BKG_INDEX_TBL_PKG' where date not between date('$BKG_BATCH_FIRST_STARTED') and date('$TODAY') group by owner_id;"
        sqlite3 "$BKG_INDEX_DB" "$query" | awk '{print $1"/"$2}' | env_parallel --lb save_owner
        echo "Read known owners"
    fi

    # add more owners
    if [ -s "$BKG_OWNERS" ]; then
        echo "Reading requested owners..."
        sed -i '/^\s*$/d' "$BKG_OWNERS"
        echo >>"$BKG_OWNERS"
        awk 'NF' "$BKG_OWNERS" >owners.tmp && mv owners.tmp "$BKG_OWNERS"
        sed -i 's/^[[:space:]]*//;s/[[:space:]]*$//' "$BKG_OWNERS"
        env_parallel --lb add_owner <"$BKG_OWNERS"
        echo >"$BKG_OWNERS"
        echo "Read requested owners"
    fi

    echo "Forking jobs..."
    get_BKG BKG_OWNERS_QUEUE | perl -pe 's/\\n/\n/g' | env_parallel --lb update_owner
    echo "Completed jobs"
    clean_up
    printf "CHANGELOG.md\n*.json\n" >.gitignore
}

main "$@"