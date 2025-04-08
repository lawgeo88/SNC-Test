@Library('jenkins-pipeline-shared') _

pipeline {
  agent any
  options {
    ansiColor colorMapName: 'XTerm'
  }
  stages {
    stage('DeployEnv') {
      when {
        expression {
          "main" != env.BRANCH_NAME
        }
      }
      steps {
        copyDpDirFilteredToS3('', '*.conf', env.BRANCH_NAME, 'dev-dp-artifact', 'contract')
        copyDpDirFilteredToS3('', '*.json', env.BRANCH_NAME, 'dev-dp-artifact', 'contract')
      }
    }
    stage('Promote ref_inf_list') {
      when {
        expression {
          "main" == env.BRANCH_NAME
        }
      }
      steps {
        copyDpDirFilteredToS3('', 'ref_inf_list', "inf", 'dev-dp-artifact', 'contract')
      }
    }
  }
}
