package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"gitlab.com/NebulousLabs/Sia/node/api/client"
	"gitlab.com/NebulousLabs/Sia/types"
)

const (
	initialWait        = 30 * time.Second
	retryInterval      = 120 * time.Second
	defaultAllowance   = 30 // SC
	configFileTemplate = "%s/trysia/allowance"
)

func main() {
	options, err := client.DefaultOptions()
	if err != nil {
		log.Fatal(err)
	}
	httpClient := client.New(options)

	configDir, err := os.UserConfigDir()
	if err != nil {
		log.Fatal(err)
	}
	configFile := fmt.Sprintf(configFileTemplate, configDir)

	allowance := uint64(defaultAllowance)
	allowanceRaw, err := ioutil.ReadFile(configFile)
	if err == nil {
		allowanceStr := string(allowanceRaw)
		allowanceStr = strings.Trim(allowanceStr, " \n")
		allowanceInt, err := strconv.Atoi(allowanceStr)
		if err == nil {
			allowance = uint64(allowanceInt)
		}
	}

	time.Sleep(initialWait)

	toggle := uint64(0)
	for {
		contracts, err := httpClient.RenterContractsGet()
		if err != nil {
			log.Fatal(err)
		}

		if len(contracts.ActiveContracts) > 0 {
			break
		}

		req := httpClient.RenterPostPartialAllowance()
		req = req.WithFunds(types.NewCurrency64(allowance).Mul(types.SiacoinPrecision))
		req = req.WithHosts(50)

		period := uint64(1008) // 1 week
		req = req.WithPeriod(types.BlockHeight(period))
		req = req.WithRenewWindow(types.BlockHeight(period / 2))

		gib := uint64(1 << 30)
		req = req.WithExpectedStorage(10*gib + toggle)
		req = req.WithExpectedUpload((10 * gib) / period)
		req = req.WithExpectedDownload((10 * gib) / period)
		req = req.WithExpectedRedundancy(3)

		err = req.Send()
		if err != nil {
			log.Fatal(err)
		}

		time.Sleep(retryInterval)

		if toggle == 0 {
			toggle = 1
		} else {
			toggle = 0
		}
	}
}
