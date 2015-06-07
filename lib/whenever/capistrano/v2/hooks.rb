require "whenever/capistrano/v2/recipes"

Capistrano::Configuration.instance(:must_exist).load do
  # Touch timestamp marker for trigering jobs that were suppose to run during
  # deploy process
  before 'deploy', 'whenever:mark_deploy_start'
  # Write the new cron jobs near the end.
  before "deploy:finalize_update", "whenever:update_crontab"
  # If anything goes wrong, undo.
  after "deploy:rollback", "whenever:update_crontab"
end
