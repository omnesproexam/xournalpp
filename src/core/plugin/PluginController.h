/*
 * Xournal++
 *
 * Plugin main controller
 *
 * @author Xournal++ Team
 * https://github.com/xournalpp/xournalpp
 *
 * @license GNU GPLv2 or later
 */

#pragma once

#include <memory>
#include <string>
#include <utility>
#include <vector>

#include <gtk/gtk.h>  // for GtkApplicationWindow

#include "Plugin.h"
#include "filesystem.h"

class Control;
class ToolMenuHandler;

class PluginController final {
public:
    explicit PluginController(Control* control);

public:
    /**
     * Register toolbar item and all other UI stuff
     */
    void registerToolbar();

    /**
     * @brief Create menu entries (one submenu per enabled plugin with menu entries)
     * The data is owned by the Plugin's themselves - do not unref the GMenuModel*
     */
    std::vector<std::pair<std::string, GMenuModel*>> createMenuSections(GtkApplicationWindow* win);

    /**
     * Add toolbar buttons
     */
    void registerToolButtons(ToolMenuHandler* toolMenuHandler);

    /**
     * Show Plugin manager Dialog
     */
    void showPluginManager() const;

    /**
     * Call a string callback on an enabled plugin identified by name.
     * Returns true if the plugin was found and the Lua callback succeeded.
     */
    bool callPluginFunction(const std::string& pluginName,
                            const std::string& functionName,
                            const std::string& argument);

private:
    /**
     * The main controller
     */
    Control* control;

    /**
     * All loaded Plugins, sorted by name and path
     * Todo: replace with boost::flat_map
     */
    std::vector<std::unique_ptr<Plugin>> plugins;
};
