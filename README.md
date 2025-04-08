# Blueprint Environment Files

## Branching strategy

* "main" may periodically receive "merges" from outside the system (from dp-blueprint) for any basic changes to the environment files
* Each environment has its own branch with its own files.
* Each QA can have their own branches, as needed, based on environment branches.
* Note: This is a reverse flow compared to how we normally move data (from feature branches, through develop, into main). This is because changes to the environment repo happen outside the system (in dp-blueprint) and need to trickle down from main into all of the environment's branches.

## Deployment strategy
* Jenkinsfile will automatically deploy to applicable environment.
* Jenkins automatically deploys to dev-dp-artifact even for stg and prod environment branches. To push files into stg-dp-artifact and prod-dp-artifact, there is a push-button process.

## Release updates
* The iterate_versions.sh script will update the dp core version referenced in the env.conf file of a specified branch or of a predefined list of branches.

### Usage: 

    ./iterate_version.sh [test] BRANCH CUR_VERSION NEW_VERSION
           BRANCH: Name of the branch to update or RELEASE to update all release branches.
           CUR_VERSION: Current Release Version.
           NEW_VERSION: (Optional) Next Release Version.
           By prefixing with test you can make sure that things are ok before actually pushing your changes

Example:

    E.g. if 1.25 is released and we are releasing 1.26 then you can specify either:
        ./iterate_version.sh RELEASE 1.25 1.26
    or
        ./iterate_version.sh RELEASE 1.25

    E.g. if 1.25 is released and we are releasing 2.0 then you can specify either:
        ./iterate_version.sh RELEASE 1.25 2.0


