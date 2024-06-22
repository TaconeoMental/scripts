PIO_DEFAULT_DEVICE := "/dev/ttyUSB0"

_default:
    @just --justfile {{justfile()}} --list --unsorted

chmod:
    sudo chmod a+rw {{pio_device}}
alias ch := chmod

run TARGET *ARGS:
    pio run --target {{TARGET}} {{ARGS}}
alias r := run

devices:
    pio device list
alias devs := devices

pio_device := env_var_or_default("pio_device", PIO_DEFAULT_DEVICE)
monitor *ARGS:
    pio device monitor --port {{pio_device}} --filter esp32_exception_decoder {{ARGS}}
alias m := monitor

upload:
    pio run --target upload --upload-port {{pio_device}}
