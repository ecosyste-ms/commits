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

ActiveRecord::Schema[8.1].define(version: 2026_03_25_131003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "commits", force: :cascade do |t|
    t.string "author"
    t.string "co_author_email"
    t.string "committer"
    t.datetime "created_at", null: false
    t.boolean "merge"
    t.string "message"
    t.integer "repository_id"
    t.string "sha"
    t.integer "stats", default: [], array: true
    t.datetime "timestamp"
    t.datetime "updated_at", null: false
    t.index ["co_author_email"], name: "index_commits_on_co_author_email", where: "(co_author_email IS NOT NULL)"
    t.index ["repository_id", "sha"], name: "index_commits_on_repository_id_and_sha_unique", unique: true
  end

  create_table "committers", force: :cascade do |t|
    t.integer "commits_count", default: 0
    t.datetime "created_at", null: false
    t.string "emails", array: true
    t.boolean "hidden", default: false, null: false
    t.integer "host_id"
    t.string "login"
    t.datetime "updated_at", null: false
    t.index ["emails"], name: "index_committers_on_emails", using: :gin
    t.index ["host_id", "login"], name: "index_committers_on_host_id_and_login"
  end

  create_table "contributions", force: :cascade do |t|
    t.integer "commit_count"
    t.bigint "committer_id", null: false
    t.datetime "created_at", null: false
    t.bigint "repository_id", null: false
    t.datetime "updated_at", null: false
    t.index ["committer_id"], name: "index_contributions_on_committer_id"
    t.index ["repository_id"], name: "index_contributions_on_repository_id"
  end

  create_table "exports", force: :cascade do |t|
    t.string "bucket_name"
    t.integer "commits_count"
    t.datetime "created_at", null: false
    t.string "date"
    t.datetime "updated_at", null: false
  end

  create_table "hosts", force: :cascade do |t|
    t.boolean "can_crawl_api", default: true
    t.bigint "commits_count"
    t.bigint "contributors_count"
    t.datetime "created_at", null: false
    t.text "host_url"
    t.string "icon_url"
    t.string "kind"
    t.text "last_error"
    t.datetime "last_synced_at"
    t.string "name"
    t.boolean "online", default: true
    t.bigint "owners_count", default: 0
    t.text "owners_url"
    t.integer "repositories_count"
    t.text "repositories_url"
    t.float "response_time"
    t.string "status", default: "pending"
    t.datetime "status_checked_at"
    t.datetime "updated_at", null: false
    t.string "url"
  end

  create_table "owners", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "hidden", default: false
    t.integer "host_id"
    t.string "login"
    t.datetime "updated_at", null: false
    t.index ["host_id", "login"], name: "index_owners_on_host_id_and_login", unique: true
  end

  create_table "repositories", force: :cascade do |t|
    t.boolean "archived"
    t.json "committers"
    t.datetime "created_at", null: false
    t.float "dds"
    t.string "default_branch", default: "master"
    t.string "description"
    t.boolean "fork"
    t.string "full_name"
    t.integer "host_id"
    t.string "icon_url"
    t.datetime "last_synced_at"
    t.string "last_synced_commit"
    t.float "mean_commits"
    t.string "owner"
    t.json "past_year_committers"
    t.float "past_year_dds"
    t.float "past_year_mean_commits"
    t.integer "past_year_total_bot_commits"
    t.integer "past_year_total_bot_committers"
    t.integer "past_year_total_commits"
    t.integer "past_year_total_committers"
    t.integer "size"
    t.integer "stargazers_count"
    t.string "status"
    t.integer "total_bot_commits"
    t.integer "total_bot_committers"
    t.integer "total_commits"
    t.integer "total_committers"
    t.datetime "updated_at", null: false
    t.index "host_id, lower((full_name)::text)", name: "index_repositories_on_host_id_lower_full_name", unique: true
    t.index ["host_id", "owner"], name: "index_repositories_on_host_id_and_owner"
  end

  add_foreign_key "contributions", "committers"
  add_foreign_key "contributions", "repositories"
end
