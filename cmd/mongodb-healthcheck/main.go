// Copyright 2024
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"log"
	"os"

	"github.com/vtomasr5/mongodb-tools/healthcheck"
	"github.com/vtomasr5/mongodb-tools/internal/db"
	"github.com/vtomasr5/mongodb-tools/internal/tool"
	"github.com/vtomasr5/mongodb-tools/pkg"
)

var (
	GitCommit string
	GitBranch string
)

func main() {
	app, _ := tool.New("Performs health and readiness checks for MongoDB", GitCommit, GitBranch)

	k8sCmd := app.Command("k8s", "Performs liveness check for MongoDB on Kubernetes")
	livenessCmd := k8sCmd.Command("liveness", "Run a liveness check of MongoDB").Default()
	_ = k8sCmd.Command("readiness", "Run a readiness check of MongoDB")
	startupDelaySeconds := livenessCmd.Flag("startupDelaySeconds", "").Default("7200").Uint64()
	component := k8sCmd.Flag("component", "").Default("mongod").String()

	cnf := db.NewConfig(
		app,
		pkg.EnvMongoDBClusterMonitorUser,
		pkg.EnvMongoDBClusterMonitorPassword,
	)

	command, err := app.Parse(os.Args[1:])
	if err != nil {
		log.Fatalf("Cannot parse command line: %s", err)
	}

	sslConf := db.SSLConfig{}
	cnf.SSL = &sslConf
	cnf.SSL.Insecure = true

	session, err := db.GetSession(cnf)
	if err != nil {
		log.Printf("ssl connection error: " + err.Error())
	}

	if session == nil {
		cnf.SSL = nil
		session, err = db.GetSession(cnf)
		if err != nil {
			log.Fatalf("Error connecting to mongodb: %s", err)
			return
		}
	}

	defer session.Close()

	switch command {
	case "k8s liveness":
		log.Printf("Running Kubernetes liveness check for %s", *component)
		switch *component {
		case "mongod":
			memberState, err := healthcheck.HealthCheckMongodLiveness(session, int64(*startupDelaySeconds))
			if err != nil {
				log.Fatal(err.Error())
				session.Close()
				os.Exit(1)
			}
			log.Printf("Member passed Kubernetes liveness check with replication state: %s", memberState)
		case "mongos":
			err := healthcheck.HealthCheckMongosLiveness(session)
			if err != nil {
				log.Fatal(err.Error())
				session.Close()
				os.Exit(1)
			}
		}
	case "k8s readiness":
		log.Printf("Running Kubernetes readiness check for %s", *component)
		switch *component {
		case "mongod":
			log.Fatal("readiness check for mongod is not implemented")
			session.Close()
			os.Exit(1)
		case "mongos":
			err := healthcheck.MongosReadinessCheck(session)
			if err != nil {
				log.Fatal(err.Error())
				session.Close()
				os.Exit(1)
			}
		}
	}
}
