#include <libconfig.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    config_t config;
    config_init(&config);
    if (!config_read_file(&config, argv[1])) {
        fprintf(stderr, "%s:%d: %s\n", argv[1],
                config_error_line(&config), config_error_text(&config));
        config_destroy(&config);
        return 1;
    }
    config_destroy(&config);
    puts("Configuration syntax is valid.");
    return 0;
}
