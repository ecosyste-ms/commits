# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_02_133807) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "commits", force: :cascade do |t|
    t.integer "repository_id"
    t.string "sha"
    t.string "message"
    t.datetime "timestamp"
    t.boolean "merge"
    t.string "author"
    t.string "committer"
    t.integer "stats", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id", "sha"], name: "index_commits_on_repository_id_and_sha_unique", unique: true
  end

  create_table "committers", force: :cascade do |t|
    t.integer "host_id"
    t.string "emails", array: true
    t.string "login"
    t.integer "commits_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["emails"], name: "index_committers_on_emails", using: :gin
    t.index ["host_id"], name: "index_committers_on_host_id"
  end

  create_table "contributions", force: :cascade do |t|
    t.bigint "committer_id", null: false
    t.bigint "repository_id", null: false
    t.integer "commit_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["committer_id"], name: "index_contributions_on_committer_id"
    t.index ["repository_id"], name: "index_contributions_on_repository_id"
  end

  create_table "exports", force: :cascade do |t|
    t.string "date"
    t.string "bucket_name"
    t.integer "commits_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "hosts", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "kind"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "repositories_count"
    t.bigint "commits_count"
    t.bigint "contributors_count"
    t.string "icon_url"
    t.bigint "owners_count", default: 0
    t.string "status", default: "pending"
    t.boolean "online", default: true
    t.datetime "status_checked_at"
    t.float "response_time"
    t.text "last_error"
    t.boolean "can_crawl_api", default: true
    t.text "host_url"
    t.text "repositories_url"
    t.text "owners_url"
  end

  create_table "jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "sidekiq_id"
    t.string "status"
    t.string "url"
    t.string "ip"
    t.json "results"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_jobs_on_status"
  end

  create_table "repositories", force: :cascade do |t|
    t.integer "host_id"
    t.string "full_name"
    t.string "default_branch", default: "master"
    t.json "committers"
    t.integer "total_commits"
    t.integer "total_committers"
    t.float "mean_commits"
    t.float "dds"
    t.datetime "last_synced_at"
    t.string "last_synced_commit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "past_year_committers"
    t.integer "past_year_total_commits"
    t.integer "past_year_total_committers"
    t.float "past_year_mean_commits"
    t.float "past_year_dds"
    t.string "status"
    t.integer "total_bot_commits"
    t.integer "total_bot_committers"
    t.integer "past_year_total_bot_commits"
    t.integer "past_year_total_bot_committers"
    t.string "owner"
    t.string "description"
    t.integer "stargazers_count"
    t.boolean "fork"
    t.boolean "archived"
    t.string "icon_url"
    t.integer "size"
    t.index "host_id, lower((full_name)::text)", name: "index_repositories_on_host_id_lower_full_name", unique: true
  end

  add_foreign_key "contributions", "committers"
  add_foreign_key "contributions", "repositories"
end
