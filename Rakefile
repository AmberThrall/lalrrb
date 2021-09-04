# frozen_string_literal: true

require "bundler/gem_tasks"

task default: :build

namespace :examples do |ns|
  FileList["examples/*.rb"].each do |path|
    basename = File.basename(path, ".rb")
    
    desc "Run example #{basename}"
    task basename do
      ruby path
    end
  end

  desc "Run every example"
  task :all do |t|
    ns.tasks.filter { |task| task != t }.each do |task|
      Rake::Task[task].execute
      puts ""
    end
  end
end
