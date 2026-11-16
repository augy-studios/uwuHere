#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <string.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#if defined(GDK_WINDOWING_X11) && defined(UWUHERE_X11)
#include <X11/Xatom.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// The compositor's blur behind the window, for the Frosted Glass look (lib/desktop/backdrop.dart).
// KWin's (and Deepin's deepin-kwin's) on X11: _KDE_NET_WM_BLUR_BEHIND_REGION on the window, with
// no region meaning all of it. The compositor puts that name on the root window while its blur is
// on, which is how to know it will blur. Wayland compositors (COSMIC's among them) have no way to
// ask yet, so it's false there and the app draws its own glows instead.
static gboolean set_blur(MyApplication* self, gboolean on) {
#if defined(GDK_WINDOWING_X11) && defined(UWUHERE_X11)
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(self->window));
  if (gdk_window == nullptr || !GDK_IS_X11_WINDOW(gdk_window)) return FALSE;
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(self->window));
  if (!gdk_screen_is_composited(screen) ||
      gdk_window_get_visual(gdk_window) != gdk_screen_get_rgba_visual(screen)) {
    return FALSE;
  }
  Display* display = GDK_DISPLAY_XDISPLAY(gdk_window_get_display(gdk_window));
  Window xid = GDK_WINDOW_XID(gdk_window);
  Atom blur = XInternAtom(display, "_KDE_NET_WM_BLUR_BEHIND_REGION", False);

  gboolean offered = FALSE;
  int count = 0;
  Atom* names = XListProperties(display, DefaultRootWindow(display), &count);
  for (int i = 0; names != nullptr && i < count; i++) {
    if (names[i] == blur) offered = TRUE;
  }
  if (names != nullptr) XFree(names);

  GdkRGBA background;
  if (on && offered) {
    XChangeProperty(display, xid, blur, XA_CARDINAL, 32, PropModeReplace, nullptr, 0);
    gdk_rgba_parse(&background, "#00000000");
  } else {
    XDeleteProperty(display, xid, blur);
    gdk_rgba_parse(&background, "#000000");
  }
  fl_view_set_background_color(self->view, &background);
  XFlush(display);
  return on && offered;
#else
  return FALSE;
#endif
}

// The app's own channel (org.uwuapps.here/desktop, lib/desktop/runner.dart). On Linux it answers
// setBackdrop only; single instance and links are done in Dart (lib/desktop/desk.dart).
static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(call), "setBackdrop") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    gboolean blur = FALSE;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* kind = fl_value_lookup_string(args, "kind");
      blur = kind != nullptr && fl_value_get_type(kind) == FL_VALUE_TYPE_STRING &&
             strcmp(fl_value_get_string(kind), "blur") == 0;
    }
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(set_blur(self, blur))));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // The app draws its own title bar (lib/desktop/chrome.dart), so no header bar here.
  gtk_window_set_title(window, "uwuHere");

  gtk_window_set_default_size(window, 1120, 760);

  // A see-through window where the compositor can show one, for the Frosted Glass look's blur
  // (set_blur). The app paints every pixel in the other looks, so nothing shows through there.
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* rgba = gdk_screen_get_rgba_visual(screen);
  if (rgba != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(GTK_WIDGET(window), rgba);
    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  self->window = window;
  self->view = view;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "org.uwuapps.here/desktop", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self,
                                            nullptr);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  // Each desktop widget is a window with an engine of its own: it gets the same plugins.
  desktop_multi_window_plugin_set_window_created_callback([](FlPluginRegistry* registry) {
    fl_register_plugins(registry);
  });

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
