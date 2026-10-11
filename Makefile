CFLAGS ?= -fPIC -O3 -Wall -Wextra
LDFLAGS ?=

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
else
	LDFLAGS += -shared
endif

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~s/include", [code:root_dir() ++ "/erts-" ++ erlang:system_info(version)])' -s init stop)

DEFLATE_CFLAGS := $(shell pkg-config --cflags libdeflate 2>/dev/null)
DEFLATE_LIBS := $(shell pkg-config --libs libdeflate 2>/dev/null)

PRIV_DIR ?= priv

all: $(PRIV_DIR) cells deflate

cells: | $(PRIV_DIR)
	@$(CC) $(CFLAGS) -I$(ERTS_INCLUDE_DIR) -o $(PRIV_DIR)/cells_nif.so.tmp c_src/cells_nif.c $(LDFLAGS) \
		&& mv -f $(PRIV_DIR)/cells_nif.so.tmp $(PRIV_DIR)/cells_nif.so \
		&& rm -rf $(PRIV_DIR)/cells_nif.so.tmp.dSYM \
		|| echo "french_curve: no C compiler, cells are quantised in Elixir"

deflate: | $(PRIV_DIR)
ifeq ($(strip $(DEFLATE_LIBS)),)
	@echo "french_curve: no libdeflate, pictures are compressed with zlib"
else
	@$(CC) $(CFLAGS) $(DEFLATE_CFLAGS) -I$(ERTS_INCLUDE_DIR) -o $(PRIV_DIR)/deflate_nif.so.tmp \
		c_src/deflate_nif.c $(LDFLAGS) $(DEFLATE_LIBS) \
		&& mv -f $(PRIV_DIR)/deflate_nif.so.tmp $(PRIV_DIR)/deflate_nif.so \
		&& rm -rf $(PRIV_DIR)/deflate_nif.so.tmp.dSYM \
		|| echo "french_curve: libdeflate would not link, pictures are compressed with zlib"
endif

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

clean:
	rm -f $(PRIV_DIR)/*.so $(PRIV_DIR)/*.tmp
	rm -rf $(PRIV_DIR)/*.tmp.dSYM

.PHONY: all cells deflate clean
