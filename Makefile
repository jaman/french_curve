CFLAGS ?= -fPIC -O3 -Wall -Wextra
LDFLAGS ?=

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
else
	LDFLAGS += -shared
endif

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~s/include", [code:root_dir() ++ "/erts-" ++ erlang:system_info(version)])' -s init stop)

PRIV_DIR = priv
NIF_SO = $(PRIV_DIR)/cells_nif.so
NIF_SRC = c_src/cells_nif.c

all: $(PRIV_DIR)
	@$(CC) $(CFLAGS) -I$(ERTS_INCLUDE_DIR) -o $(NIF_SO).tmp $(NIF_SRC) $(LDFLAGS) \
		&& mv -f $(NIF_SO).tmp $(NIF_SO) && rm -rf $(NIF_SO).tmp.dSYM \
		|| echo "french_curve: no C compiler, cells are quantised in Elixir"

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

clean:
	rm -f $(NIF_SO) $(PRIV_DIR)/*.tmp
	rm -rf $(PRIV_DIR)/*.tmp.dSYM

.PHONY: all clean
