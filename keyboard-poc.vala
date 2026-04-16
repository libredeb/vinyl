using Gtk;
using GLib;

public class MultiLangKeyboard : Window {
    private Entry entry;
    private string current_layout;
    private GenericArray<string> rows;

    public MultiLangKeyboard() {
        this.title = "Teclado Internacional Dinámico";
        this.set_default_size(600, 300);
        this.window_position = WindowPosition.CENTER;
        this.destroy.connect(Gtk.main_quit);

        // 1. Detectar idioma y obtener distribución
        this.current_layout = get_layout_by_locale();
       
        // 2. Dividir el layout en filas para un control visual perfecto
        prepare_rows();

        // 3. Construir Interfaz
        setup_ui();
    }

    private string get_layout_by_locale() {
        // Inicializar el sistema de locales de GLib
        Intl.setlocale(LocaleCategory.ALL, "");
        string locale = Intl.setlocale(LocaleCategory.MESSAGES, null) ?? "en";

        // Diccionario de distribuciones (puedes añadir más fácilmente)
        var layouts = new HashTable<string, string>(str_hash, str_equal);
        layouts.insert("es", "QWERTYUIOP-ASDFGHJKLÑ-ZXCVBNM"); // El '-' separa filas
        layouts.insert("fr", "AZERTYUIOP-QSDFGHJKLM-WXCVBN");
        layouts.insert("de", "QWERTZUIOPÜ-ASDFGHJKLÖÄ-YXCVB M");
        layouts.insert("en", "QWERTYUIOP-ASDFGHJKL-ZXCVBNM");

        // Buscar por prefijo (ej: "es_MX" -> "es")
        string lang_code = locale.substring(0, 2).down();
       
        if (layouts.contains(lang_code)) {
            return layouts.lookup(lang_code);
        }
        return layouts.lookup("en"); // Por defecto inglés
    }

    private void prepare_rows() {
        rows = new GenericArray<string>();
        string[] parts = current_layout.split("-");
        foreach (string s in parts) {
            rows.add(s);
        }
    }

    private void setup_ui() {
        var main_box = new Box(Orientation.VERTICAL, 12);
        main_box.margin = 20;

        entry = new Entry();
        entry.placeholder_text = "Escribe aquí...";
        entry.height_request = 40;

        var keyboard_grid = new Grid();
        keyboard_grid.row_spacing = 6;
        keyboard_grid.column_spacing = 6;
        keyboard_grid.halign = Align.CENTER;

        // Construir el teclado fila por fila
        for (int r = 0; r < rows.length; r++) {
            string row_content = rows.get(r);
            int row_len = row_content.char_count();

            for (int c = 0; c < row_len; c++) {
                // Obtener el caracter Unicode correctamente
                string key = row_content.get_char(row_content.index_of_nth_char(c)).to_string();
               
                var btn = new Button.with_label(key);
                btn.set_size_request(45, 45);
               
                // Estilo CSS básico para que se vea moderno
                btn.get_style_context().add_class("keyboard-key");

                btn.clicked.connect(() => {
                    entry.text += key;
                    entry.grab_focus();
                    entry.set_position(-1);
                });

                keyboard_grid.attach(btn, c, r, 1, 1);
            }
        }

        main_box.pack_start(keyboard_grid, true, true, 0);
        main_box.pack_start(entry, false, false, 0);

        this.add(main_box);
    }

    public static int main(string[] args) {
        Gtk.init(ref args);
        var app = new MultiLangKeyboard();
        app.show_all();
        Gtk.main();
        return 0;
    }
}