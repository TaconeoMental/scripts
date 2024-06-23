package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"math/rand"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
	"unsafe"
)

var MyIp string

// https://stackoverflow.com/a/31832326
var randomSrc = rand.NewSource(time.Now().UnixNano())

const letterBytes = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
const (
	letterIdxBits = 6                    // 6 bits to represent a letter index
	letterIdxMask = 1<<letterIdxBits - 1 // All 1-bits, as many as letterIdxBits
	letterIdxMax  = 63 / letterIdxBits   // # of letter indices fitting in 63 bits
)

func RandStringBytesMaskImprSrcUnsafe(n int) string {
	b := make([]byte, n)
	// A src.Int63() generates 63 random bits, enough for letterIdxMax characters!
	for i, cache, remain := n-1, randomSrc.Int63(), letterIdxMax; i >= 0; {
		if remain == 0 {
			cache, remain = randomSrc.Int63(), letterIdxMax
		}
		if idx := int(cache & letterIdxMask); idx < len(letterBytes) {
			b[i] = letterBytes[idx]
			i--
		}
		cache >>= letterIdxBits
		remain--
	}

	return *(*string)(unsafe.Pointer(&b))
}

type Proxy struct {
	URL        string
	Anonymous  bool
	httpClient *http.Client
	Latency    float64 // Seconds
}

func ProxyAwareHttpClient(proxyServer string) (*http.Client, error) {
	proxyUrl, err := url.Parse(proxyServer)
	if err != nil {
		msg := fmt.Sprintf("Invalid proxy url %q\n", proxyServer)
		return nil, errors.New(msg)
	}

	httpTransport := &http.Transport{
		Proxy: http.ProxyURL(proxyUrl),
	}
	httpClient := &http.Client{Transport: httpTransport}
	return httpClient, nil
}

func NewProxy(proxyServer string) (*Proxy, error) {
	proxy := &Proxy{URL: proxyServer}

	httpClient, err := ProxyAwareHttpClient(proxyServer)
	if err != nil {
        return nil, fmt.Errorf("Proxy creation error: %w", err)
	}
	proxy.httpClient = httpClient

	//response, err := httpClient.Get("http://azenv.net/")
    req, err := http.NewRequest("GET", "https://httpbin.org/get?show_env", nil)
	if err != nil {
        return nil, fmt.Errorf("Proxy network error: %w", err)
	}
	randHeaderVal := RandStringBytesMaskImprSrcUnsafe(8)
	req.Header.Add("RANDHEADER", randHeaderVal)

	timeStart := time.Now() // Super mala esta métrica, pero sirve para este fin
	response, err := httpClient.Do(req)
	if err != nil {
        return nil, fmt.Errorf("Proxy request error: %w", err)
	}
	proxy.Latency = time.Since(timeStart).Seconds()

	body, _ := ioutil.ReadAll(response.Body)
	bodyStr := string(body)

	if !strings.Contains(bodyStr, randHeaderVal) {
		return nil, fmt.Errorf("%s returned cached response", proxyServer)
	}

	if strings.Contains(bodyStr, MyIp) {
		proxy.Anonymous = false
	} else {
		proxy.Anonymous = true
	}

	return proxy, nil
}

func worker(proxies chan string, results chan *Proxy, wg *sync.WaitGroup) {
	defer wg.Done()
	for proxyServer := range proxies {
		proxyObject, err := NewProxy(proxyServer)
		if err != nil {
			//fmt.Println(err.Error())
			continue
		}

		if proxyObject.Anonymous {
			results <- proxyObject
		}
	}
}

func GetMyIP() (string, error) {
	resp, err := http.Get("https://ifconfig.cl/ip")
	if err != nil {
		return "", errors.New("Could not determine your public IP address. Try passing it manually with the '-ip' flag")
	}
	body, _ := ioutil.ReadAll(resp.Body)
	return strings.TrimSpace(string(body)), nil
}

func main() {
	var wg sync.WaitGroup
    proxyFilePath := flag.String("proxies", "", "File with http proxies in ip:port format")
    ipAddress := flag.String("ip", "", "Optional: Your public IP address")
	maxTimeout := flag.Int("timeout", -1, "Connection timeout")
	workerCount := flag.Int("workers", 1000, "Worker count")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: %s [Options]\n", os.Args[0])
		fmt.Fprintln(os.Stderr, "Options:")

		flag.VisitAll(func(f *flag.Flag) {
			fmt.Fprintf(os.Stderr, "    -%v,\t%v\n", f.Name, f.Usage)
		})
	}
	flag.Parse()

	if *maxTimeout < 1 {
        fmt.Fprintf(os.Stderr, "[-] -timeout option required\n")
		flag.Usage()
		os.Exit(1)
	}

	if *proxyFilePath == "" {
		fmt.Fprintf(os.Stderr, "[-] -proxies option required\n")
		flag.Usage()
		os.Exit(1)
	}

	proxyFile, err := os.Open(*proxyFilePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[-] Error opening file '%v'\n", *proxyFilePath)
		os.Exit(1)
	}
	defer proxyFile.Close()

	if *ipAddress != "" {
		MyIp = *ipAddress
	} else {
		MyIp, err = GetMyIP()
		if err != nil {
			log.Fatal(err)
		}
	}

	proxies := make(chan string)
	results := make(chan *Proxy)

	for i := 0; i < *workerCount; i++ {
		wg.Add(1)
		go worker(proxies, results, &wg)
	}

	scanner := bufio.NewScanner(proxyFile)
	wg.Add(1)
	go func() {
		for scanner.Scan() {
			proxies <- scanner.Text()
		}
		wg.Done()
		close(proxies)
	}()

	for p := range results {
		if p.Latency > float64(*maxTimeout)+1 {
			// No es la manera correcta de hacerlo, pero funciona ;)
			return
		}
		fmt.Println(p.URL)
	}

	wg.Wait()
}
