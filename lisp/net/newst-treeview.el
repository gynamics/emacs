;;; newst-treeview.el --- Treeview frontend for newsticker.  -*- lexical-binding:t -*-

;; Copyright (C) 2008-2025 Free Software Foundation, Inc.

;; Author:      Ulf Jasper <ulf.jasper@web.de>
;; Created:     2007
;; Keywords:    News, RSS, Atom
;; Package:     newsticker

;; ======================================================================

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;; ======================================================================
;;; Commentary:

;; See newsticker.el

;; ======================================================================
;;; Code:
(require 'cl-lib)
(require 'newst-reader)
(require 'widget)
(require 'tree-widget)
(require 'wid-edit)

;; ======================================================================
;;; Customization
;; ======================================================================
(defgroup newsticker-treeview nil
  "Settings for the tree view reader."
  :group 'newsticker-reader)

(defface newsticker-treeview-face
  '((((class color) (background dark))  :foreground "white")
    (((class color) (background light)) :foreground "black"))
  "Face for newsticker tree.")

(defface newsticker-treeview-new-face
  '((t :inherit newsticker-treeview-face :weight bold))
  "Face for newsticker tree.")

(defface newsticker-treeview-old-face
  '((t :inherit newsticker-treeview-face))
  "Face for newsticker tree.")

(defface newsticker-treeview-immortal-face
  '((default :inherit newsticker-treeview-face :slant italic)
    (((class color) (background dark))  :foreground "orange")
    (((class color) (background light)) :foreground "blue"))
  "Face for newsticker tree.")

(defface newsticker-treeview-obsolete-face
  '((t :inherit newsticker-treeview-face :strike-through t))
  "Face for newsticker tree.")

(defface newsticker-treeview-selection-face
  '((((class color) (background dark))  :background "#4444aa")
    (((class color) (background light)) :background "#bbbbff"))
  "Face for newsticker selection.")

(defcustom newsticker-treeview-date-format
  "%d.%m.%y, %H:%M"
  "Format for the date column in the treeview list buffer.
See `format-time-string' for a list of valid specifiers."
  :version "25.1"
  :type 'string)

(defcustom newsticker-treeview-own-frame
  nil
  "Decides whether newsticker treeview creates and uses its own frame."
  :type 'boolean)

(defcustom newsticker-treeview-treewindow-width
  30
  "Width of tree window in treeview layout.
See also `newsticker-treeview-listwindow-height'."
  :type 'integer)

(defcustom newsticker-treeview-listwindow-height
  10
  "Height of list window in treeview layout.
See also `newsticker-treeview-treewindow-width'."
  :type 'integer)

(defcustom newsticker-treeview-automatically-mark-displayed-items-as-old
  t
  "Decides whether to automatically mark displayed items as old.
If t an item is marked as old as soon as it is displayed.  This
applies to newsticker only."
  :type 'boolean)

(defcustom newsticker-treeview-use-feed-name-from-url-list-in-treeview
  t
  "Use the feed names from `newsticker-url-list' for display in treeview."
  :version "28.1"
  :type 'boolean)

(defcustom newsticker-treeview-use-feed-name-from-url-list-in-itemview
  t
  "Use feed names from `newsticker-url-list' in itemview."
  :version "28.1"
  :type 'boolean)

(defvar newsticker-groups
  '("Feeds")
  "List of feed groups, used in the treeview frontend.
First element is a string giving the group name.  Remaining
elements are either strings giving a feed name or lists having
the same structure as `newsticker-groups'. (newsticker-groups :=
groupdefinition, groupdefinition := groupname groupcontent*,
groupcontent := feedname | groupdefinition)

Example: (\"Topmost group\" \"feed1\" (\"subgroup1\" \"feed 2\")
\"feed3\")")

;; ======================================================================
;;; internal variables
;; ======================================================================
(defvar newsticker--treeview-windows nil)
(defvar newsticker--treeview-buffers nil)
(defvar newsticker--treeview-current-feed nil
  "Feed name of currently shown item.")
(defvar newsticker--treeview-current-vfeed nil)
(defvar newsticker--treeview-list-show-feed nil)
(defvar newsticker--saved-window-config nil)
(defvar newsticker--selection-overlay nil
  "Highlight the selected tree node.")
(defvar newsticker--tree-selection-overlay nil
  "Highlight the selected list item.")
(defvar newsticker--frame nil "Special frame for newsticker windows.")
(defvar newsticker--treeview-list-sort-order 'sort-by-time)
(defvar newsticker--treeview-current-node-id nil)
(defvar newsticker--treeview-current-tree nil)
(defvar newsticker--treeview-feed-tree nil)
(defvar newsticker--treeview-vfeed-tree nil)

(declare-function newsticker-handle-url "newst-plainview" ())

;; maps for the clickable portions
(defvar newsticker--treeview-url-keymap
  (let ((map (make-sparse-keymap 'newsticker--treeview-url-keymap)))
    (define-key map [mouse-1] #'newsticker-treeview-mouse-browse-url)
    (define-key map [mouse-2] #'newsticker-treeview-mouse-browse-url)
    (define-key map "\n" #'newsticker-treeview-browse-url)
    (define-key map "\C-m" #'newsticker-treeview-browse-url)
    (define-key map [(control return)] #'newsticker-handle-url)
    map)
  "Key map for click-able headings in the newsticker treeview buffers.")


;; ======================================================================
;;; short cuts
;; ======================================================================
(defsubst newsticker--treeview-tree-buffer ()
  "Return the tree buffer of the newsticker treeview."
  (nth 0 newsticker--treeview-buffers))
(defsubst newsticker--treeview-list-buffer ()
  "Return the list buffer of the newsticker treeview."
  (nth 1 newsticker--treeview-buffers))
(defsubst newsticker--treeview-item-buffer ()
  "Return the item buffer of the newsticker treeview."
  (nth 2 newsticker--treeview-buffers))
(defsubst newsticker--treeview-tree-window ()
  "Return the tree window of the newsticker treeview."
  (nth 0 newsticker--treeview-windows))
(defsubst newsticker--treeview-list-window ()
  "Return the list window of the newsticker treeview."
  (nth 1 newsticker--treeview-windows))
(defsubst newsticker--treeview-item-window ()
  "Return the item window of the newsticker treeview."
  (nth 2 newsticker--treeview-windows))

;; ======================================================================
;;; utility functions
;; ======================================================================
(defun newsticker--treeview-get-id (parent i)
  "Create an id for a newsticker treeview node.
PARENT is the node's parent, I is an integer."
  ;;(message "newsticker--treeview-get-id %s"
  ;;       (format "%s-%d" (widget-get parent :nt-id) i))
  (format "%s-%d" (widget-get parent :nt-id) i))

(defun newsticker--treeview-ids-eq (id1 id2)
  "Return non-nil if ids ID1 and ID2 are equal."
  ;;(message "%s/%s" (or id1 -1) (or id2 -1))
  (and id1 id2 (string= id1 id2)))

(defun newsticker--treeview-nodes-eq (node1 node2)
  "Compare treeview nodes NODE1 and NODE2 for equality.
Nodes are equal if the have the same newsticker-id.  Note that
during re-tagging and collapsing/expanding nodes change, while
their id stays constant."
  (let ((id1 (widget-get node1 :nt-id))
        (id2 (widget-get node2 :nt-id)))
    ;;(message "%s/%s %s/%s" (widget-get node1 :tag) (widget-get node2 :tag)
    ;;       (or id1 -1) (or id2 -1))
    (or (newsticker--treeview-ids-eq id1 id2)
        (string= (widget-get node1 :nt-feed) (widget-get node2 :nt-feed)))))

(defun newsticker--treeview-do-get-node-of-feed (feed-name startnode)
   "Recursively search node for feed FEED-NAME starting from STARTNODE."
   ;;(message "%s/%s" feed-name (widget-get startnode :nt-feed))
   (if (string= feed-name (or (widget-get startnode :nt-feed)
                              (widget-get startnode :nt-vfeed)))
       (throw 'found startnode)
     (let ((children (widget-get startnode :children)))
       (dolist (w children)
         (newsticker--treeview-do-get-node-of-feed feed-name w)))))

(defun newsticker--treeview-get-node-of-feed (feed-name)
  "Return node for feed FEED-NAME in newsticker treeview tree."
  (catch 'found
    (newsticker--treeview-do-get-node-of-feed feed-name
                                              newsticker--treeview-feed-tree)
    (newsticker--treeview-do-get-node-of-feed feed-name
                                              newsticker--treeview-vfeed-tree)))

(defun newsticker--treeview-do-get-node-by-id (id startnode)
   "Recursively search node with ID starting from STARTNODE."
   (if (newsticker--treeview-ids-eq id (widget-get startnode :nt-id))
       (throw 'found startnode)
     (let ((children (widget-get startnode :children)))
       (dolist (w children)
         (newsticker--treeview-do-get-node-by-id id w)))))

(defun newsticker--treeview-get-node-by-id (id)
  "Return node with ID in newsticker treeview tree."
  (catch 'found
    (newsticker--treeview-do-get-node-by-id id newsticker--treeview-feed-tree)
    (newsticker--treeview-do-get-node-by-id id newsticker--treeview-vfeed-tree)))

(defun newsticker--treeview-get-current-node ()
  "Return current node in newsticker treeview tree."
  (newsticker--treeview-get-node-by-id newsticker--treeview-current-node-id))

;; ======================================================================

(declare-function w3m-toggle-inline-images "ext:w3m" (&optional force no-cache))
(defvar w3m-fill-column)

(defun newsticker--treeview-render-text (start end)
  "Render text between markers START and END."
  (if newsticker-html-renderer
      (condition-case error-data
          ;; Need to save selected window in order to prevent mixing
          ;; up contents of the item buffer.  This happens with shr
          ;; which does some smart optimizations that apparently
          ;; interfere with our own, maybe not-so-smart, optimizations.
          (save-selected-window
            (save-excursion
              (set-marker-insertion-type end t)
              ;; check whether it is necessary to call html renderer
              ;; (regexp inspired by htmlr.el)
              (goto-char start)
              (when (re-search-forward
                     "</?[A-Za-z1-6]*\\|&#?[A-Za-z0-9]+;" end t)
                ;; (message "%s" (newsticker--title item))
                (let ((w3m-fill-column (if newsticker-use-full-width
                                           -1 fill-column)))
                  (select-window (newsticker--treeview-item-window))
                  (save-excursion
                    (funcall newsticker-html-renderer start end)))
                ;;(cond ((eq newsticker-html-renderer 'w3m-region)
                ;;     (add-text-properties start end (list 'keymap
                ;;                                        w3m-minor-mode-map)))
                (if (eq newsticker-html-renderer 'w3m-region)
                    (w3m-toggle-inline-images t))
                t)))
        (error
         (message "Error: HTML rendering failed: %s, %s"
                  (car error-data) (cdr error-data))
         nil))
    nil))

;; ======================================================================
;;; List window
;; ======================================================================
(defun newsticker--treeview-list-add-item (item feed &optional show-feed)
  "Add news ITEM for FEED to newsticker treeview list window.
If string SHOW-FEED is non-nil it is shown in the item string."
  (setq newsticker--treeview-list-show-feed show-feed)
  (with-current-buffer (newsticker--treeview-list-buffer)
    (let* ((inhibit-read-only t)
           pos1 pos2)
      (goto-char (point-max))
      (setq pos1 (point-marker))
      (insert " ")
      (insert (propertize " " 'display '(space :align-to 2)))
      (insert (if show-feed
                  (concat
                   (substring
                    (format "%-10s" (newsticker--real-feed-name
                                     feed))
                    0 10)
                   (propertize " " 'display '(space :align-to 12)))
                ""))
      (insert (format-time-string newsticker-treeview-date-format
                                  (newsticker--time item)))
      (insert (propertize " " 'display
                          (list 'space :align-to (if show-feed 28 18))))
      (setq pos2 (point-marker))
      (insert (newsticker--title item))
      (insert "\n")
      (newsticker--treeview-render-text pos2 (point-marker))
      (goto-char pos2)
      (while (search-forward "\n" nil t)
        (replace-match " "))
      (let ((map (make-sparse-keymap)))
        (dolist (key'([mouse-1] [mouse-3]))
          (define-key map key #'newsticker-treeview-tree-click))
        (define-key map "\n" #'newsticker-treeview-show-item)
        (define-key map "\C-m" #'newsticker-treeview-show-item)
        (add-text-properties pos1 (point-max)
                             (list :nt-item item
                                   :nt-feed feed
                                   :nt-link (newsticker--link item)
                                   'mouse-face 'highlight
                                   'keymap map
                                   'help-echo (buffer-substring pos2
                                                                (point-max)))))
      (insert "\n"))))

(defun newsticker--treeview-list-clear ()
  "Clear the newsticker treeview list window."
  (with-current-buffer (newsticker--treeview-list-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (kill-all-local-variables)
      (remove-overlays))))

(defun newsticker--treeview-list-items-with-age-callback (widget
                                                          _changed-widget
                                                          &rest ages)
  "Fill newsticker treeview list window with items of certain age.
This is a callback function for the treeview nodes.
Argument WIDGET is the calling treeview widget.
Argument CHANGED-WIDGET is the widget that actually has changed.
Optional argument AGES is the list of ages that are to be shown."
  (newsticker--treeview-list-clear)
  (widget-put widget :nt-selected t)
  (apply #'newsticker--treeview-list-items-with-age ages))

(defun newsticker--treeview-list-items-with-age (&rest ages)
  "Actually fill newsticker treeview list window with items of certain age.
AGES is the list of ages that are to be shown."
  (mapc (lambda (feed)
          (let ((feed-name-symbol (intern (car feed))))
            (mapc (lambda (item)
                    (when (or (memq 'all ages)
                              (memq (newsticker--age item) ages))
                      (newsticker--treeview-list-add-item
                       item feed-name-symbol t)))
                  (newsticker--treeview-list-sort-items
                   (cdr (newsticker--cache-get-feed feed-name-symbol))))))
        (append newsticker-url-list-defaults newsticker-url-list))
  (newsticker--treeview-list-update nil))

(defun newsticker--treeview-list-new-items (widget changed-widget
                                                   &optional _event)
  "Fill newsticker treeview list window with new items.
This is a callback function for the treeview nodes.
Argument WIDGET is the calling treeview widget.
Argument CHANGED-WIDGET is the widget that actually has changed.
Optional argument EVENT is the mouse event that triggered this action."
  (newsticker--treeview-list-items-with-age-callback widget changed-widget
                                                     'new)
  (newsticker--treeview-item-show-text
   "New items"
   "This is a virtual feed containing all new items"))

(defun newsticker--treeview-list-immortal-items (widget changed-widget
                                                        &optional _event)
  "Fill newsticker treeview list window with immortal items.
This is a callback function for the treeview nodes.
Argument WIDGET is the calling treeview widget.
Argument CHANGED-WIDGET is the widget that actually has changed.
Optional argument EVENT is the mouse event that triggered this action."
  (newsticker--treeview-list-items-with-age-callback widget changed-widget
                                                     'immortal)
  (newsticker--treeview-item-show-text
   "Immortal items"
   "This is a virtual feed containing all immortal items."))

(defun newsticker--treeview-list-obsolete-items (widget changed-widget
                                                        &optional _event)
  "Fill newsticker treeview list window with obsolete items.
This is a callback function for the treeview nodes.
Argument WIDGET is the calling treeview widget.
Argument CHANGED-WIDGET is the widget that actually has changed.
Optional argument EVENT is the mouse event that triggered this action."
  (newsticker--treeview-list-items-with-age-callback widget changed-widget
                                                     'obsolete)
  (newsticker--treeview-item-show-text
   "Obsolete items"
   "This is a virtual feed containing all obsolete items."))

(defun newsticker--treeview-list-all-items (widget changed-widget
                                                   &optional event)
  "Fill newsticker treeview list window with all items.
This is a callback function for the treeview nodes.
Argument WIDGET is the calling treeview widget.
Argument CHANGED-WIDGET is the widget that actually has changed.
Optional argument EVENT is the mouse event that triggered this action."
  (newsticker--treeview-list-items-with-age-callback widget changed-widget
                                                     event 'new 'old
                                                     'obsolete 'immortal)
  (newsticker--treeview-item-show-text
   "All items"
   "This is a virtual feed containing all items."))

(defun newsticker--treeview-list-items-v (vfeed-name)
  "List items for virtual feed VFEED-NAME."
  (when vfeed-name
    (cond ((string-match "\\*new\\*" vfeed-name)
           (newsticker--treeview-list-items-with-age 'new))
          ((string-match "\\*immortal\\*" vfeed-name)
           (newsticker--treeview-list-items-with-age 'immortal))
          ((string-match "\\*old\\*" vfeed-name)
           (newsticker--treeview-list-items-with-age 'old nil)))
    (newsticker--treeview-list-update nil)
    ))

(defun newsticker--treeview-list-items (feed-name)
  "List items for feed FEED-NAME."
  (when feed-name
    (if (newsticker--treeview-virtual-feed-p feed-name)
        (newsticker--treeview-list-items-v feed-name)
      (mapc (lambda (item)
              (if (eq (newsticker--age item) 'feed)
                  (newsticker--treeview-item-show item (intern feed-name))
                (newsticker--treeview-list-add-item item
                                                    (intern feed-name))))
            (newsticker--treeview-list-sort-items
             (cdr (newsticker--cache-get-feed (intern feed-name)))))
      (newsticker--treeview-list-update nil))))

(defun newsticker--treeview-list-feed-items (widget _changed-widget
                                                    &optional _event)
  "Callback function for listing feed items.
Argument WIDGET is the calling treeview widget.
Argument CHANGED-WIDGET is the widget that actually has changed.
Optional argument EVENT is the mouse event that triggered this action."
  (newsticker--treeview-list-clear)
  (widget-put widget :nt-selected t)
  (let ((feed-name (widget-get widget :nt-feed))
        (vfeed-name (widget-get widget :nt-vfeed)))
    (if feed-name
        (newsticker--treeview-list-items feed-name)
      (newsticker--treeview-list-items-v vfeed-name))))

(defun newsticker--treeview-list-compare-item-by-age (item1 item2)
  "Compare two news items ITEM1 and ITEM2 wrt age."
  (catch 'result
    (let ((age1 (newsticker--age item1))
          (age2 (newsticker--age item2)))
      (cond ((eq age1 'new)
             t)
            ((eq age1 'immortal)
             (cond ((eq age2 'new)
                    t)
                   ((eq age2 'immortal)
                    t)
                   (t
                    nil)))
            ((eq age1 'old)
             (cond ((eq age2 'new)
                    nil)
                   ((eq age2 'immortal)
                    nil)
                   ((eq age2 'old)
                    nil)
                   (t
                    t)))
            (t
             nil)))))

(defun newsticker--treeview-list-compare-item-by-age-reverse (item1 item2)
  "Compare two news items ITEM1 and ITEM2 wrt age in reverse order."
  (newsticker--treeview-list-compare-item-by-age item2 item1))

(defun newsticker--treeview-list-compare-item-by-time (item1 item2)
  "Compare two news items ITEM1 and ITEM2 wrt time values."
  (newsticker--cache-item-compare-by-time item1 item2))

(defun newsticker--treeview-list-compare-item-by-time-reverse (item1 item2)
  "Compare two news items ITEM1 and ITEM2 wrt time values in reverse order."
  (newsticker--cache-item-compare-by-time item2 item1))

(defun newsticker--treeview-list-compare-item-by-title (item1 item2)
  "Compare two news items ITEM1 and ITEM2 wrt title."
  (newsticker--cache-item-compare-by-title item1 item2))

(defun newsticker--treeview-list-compare-item-by-title-reverse (item1 item2)
  "Compare two news items ITEM1 and ITEM2 wrt title in reverse order."
  (newsticker--cache-item-compare-by-title item2 item1))

(defun newsticker--treeview-list-sort-items (items)
  "Return sorted copy of list ITEMS.
The sort function is chosen according to the value of
`newsticker--treeview-list-sort-order'."
  (let ((sort-fun
         (cond ((eq newsticker--treeview-list-sort-order 'sort-by-age)
                'newsticker--treeview-list-compare-item-by-age)
               ((eq newsticker--treeview-list-sort-order
                    'sort-by-age-reverse)
                'newsticker--treeview-list-compare-item-by-age-reverse)
               ((eq newsticker--treeview-list-sort-order 'sort-by-time)
                'newsticker--treeview-list-compare-item-by-time)
               ((eq newsticker--treeview-list-sort-order
                    'sort-by-time-reverse)
                'newsticker--treeview-list-compare-item-by-time-reverse)
               ((eq newsticker--treeview-list-sort-order 'sort-by-title)
                'newsticker--treeview-list-compare-item-by-title)
               ((eq newsticker--treeview-list-sort-order
                    'sort-by-title-reverse)
                'newsticker--treeview-list-compare-item-by-title-reverse)
               (t
                'newsticker--treeview-list-compare-item-by-title))))
    (sort (copy-sequence items) sort-fun)))

(defun newsticker--treeview-list-update-faces ()
  "Update faces in the treeview list buffer."
  (let (pos-sel)
    (with-current-buffer (newsticker--treeview-list-buffer)
      (save-excursion
        (let ((inhibit-read-only t))
          (goto-char (point-min))
          (while (not (eobp))
            (let* ((pos (line-end-position))
                   (item (get-text-property (point) :nt-item))
                   (age (newsticker--age item))
                   (selected (get-text-property (point) :nt-selected))
                   (face (cond ((eq age 'new)
                                'newsticker-treeview-new-face)
                               ((eq age 'old)
                                'newsticker-treeview-old-face)
                               ((eq age 'immortal)
                                'newsticker-treeview-immortal-face)
                               ((eq age 'obsolete)
                                'newsticker-treeview-obsolete-face)
                               (t
                                'bold))))
              (put-text-property (point) pos 'face face)
              (if selected
                  (move-overlay newsticker--selection-overlay (point)
                                (1+ pos) ;include newline
                                (current-buffer)))
              (if selected (setq pos-sel (point)))
              (forward-line 1)
              (beginning-of-line)))))) ;; FIXME!?
    (when pos-sel
      (if (window-live-p (newsticker--treeview-list-window))
          (set-window-point (newsticker--treeview-list-window) pos-sel)))))

(defun newsticker--treeview-list-clear-highlight ()
  "Clear the highlight in the treeview list buffer."
  (with-current-buffer (newsticker--treeview-list-buffer)
    (let ((inhibit-read-only t))
      (put-text-property (point-min) (point-max) :nt-selected nil))
    (newsticker--treeview-list-update-faces)))

(defun newsticker--treeview-list-update-highlight ()
  "Update the highlight in the treeview list buffer."
  (newsticker--treeview-list-clear-highlight)
  (with-current-buffer (newsticker--treeview-list-buffer)
    (let ((inhibit-read-only t))
      (put-text-property (line-beginning-position) (line-end-position)
                         :nt-selected t))
    (newsticker--treeview-list-update-faces)))

(defun newsticker--treeview-list-highlight-start ()
  "Return position of selection in treeview list buffer."
  (with-current-buffer (newsticker--treeview-list-buffer)
    (save-excursion
      (goto-char (point-min))
      (next-single-property-change (point) :nt-selected))))

(defun newsticker--treeview-list-update (clear-buffer)
  "Update the faces and highlight in the treeview list buffer.
If CLEAR-BUFFER is non-nil the list buffer is completely erased."
  (save-excursion
    (if (window-live-p (newsticker--treeview-list-window))
        (set-window-buffer (newsticker--treeview-list-window)
                           (newsticker--treeview-list-buffer)))
    (set-buffer (newsticker--treeview-list-buffer))
    (if clear-buffer
        (let ((inhibit-read-only t))
          (erase-buffer)))
    (newsticker-treeview-list-mode)
    (newsticker--treeview-list-update-faces)
    (goto-char (point-min))))

(defvar-keymap newsticker-treeview-list-sort-button-map
  :doc "Local keymap for newsticker treeview list window sort buttons."
  "<header-line> <mouse-1>" #'newsticker--treeview-list-sort-by-column
  "<header-line> <mouse-2>" #'newsticker--treeview-list-sort-by-column)

(defun newsticker--treeview-list-sort-by-column (&optional event)
  "Sort the newsticker list window buffer by the column clicked on.
Optional argument EVENT is the mouse event that triggered this action."
  (interactive (list last-input-event))
  (if event (mouse-select-window event))
  (let* ((pos (event-start event))
	 (obj (posn-object pos))
	 (sort-order (if obj
                      (get-text-property (cdr obj) 'sort-order (car obj))
                    (get-text-property (posn-point pos) 'sort-order))))
    (setq newsticker--treeview-list-sort-order
          (cond ((eq sort-order 'sort-by-age)
                 (if (eq newsticker--treeview-list-sort-order 'sort-by-age)
                     'sort-by-age-reverse
                   'sort-by-age))
                ((eq sort-order 'sort-by-time)
                 (if (eq newsticker--treeview-list-sort-order 'sort-by-time)
                     'sort-by-time-reverse
                   'sort-by-time))
                ((eq sort-order 'sort-by-title)
                 (if (eq newsticker--treeview-list-sort-order 'sort-by-title)
                     'sort-by-title-reverse
                   'sort-by-title))))
    (newsticker-treeview-update)))

(defun newsticker-treeview-list-make-sort-button (name sort-order)
  "Create propertized string for headerline button.
NAME is the button text, SORT-ORDER is the associated sort order
for the button."
  (let ((face (if (string-match (symbol-name sort-order)
                                (symbol-name
                                 newsticker--treeview-list-sort-order))
                  'bold
                'header-line)))
    (propertize name
                'sort-order sort-order
                'help-echo (concat "Sort by " name)
                'mouse-face 'highlight
                'face face
                'keymap newsticker-treeview-list-sort-button-map)))

(defun newsticker--treeview-list-select (item)
  "Select ITEM in treeview's list buffer."
  (newsticker--treeview-list-clear-highlight)
  (save-current-buffer
    (set-buffer (newsticker--treeview-list-buffer))
    (goto-char (point-min))
    (catch 'found
      (while t
        (let ((it (get-text-property (point) :nt-item)))
          (when (eq it item)
            (newsticker--treeview-list-update-highlight)
            (newsticker--treeview-list-update-faces)
            (newsticker--treeview-item-show
             item (get-text-property (point) :nt-feed))
            (throw 'found t)))
        (forward-line 1)
        (when (eobp)
          (goto-char (point-min))
          (throw 'found nil))))))

;; ======================================================================
;;; item window
;; ======================================================================
(defun newsticker--treeview-item-show-text (title description)
  "Show text in treeview item buffer consisting of TITLE and DESCRIPTION."
  (with-current-buffer (newsticker--treeview-item-buffer)
    (when (fboundp 'w3m-process-stop)
      (w3m-process-stop (current-buffer)))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (kill-all-local-variables)
      (remove-overlays)
      (insert title)
      (put-text-property (point-min) (point) 'face 'newsticker-feed-face)
      (insert "\n\n" description)
      (when newsticker-justification
        (fill-region (point-min) (point-max) newsticker-justification))
      (newsticker-treeview-item-mode)
      (goto-char (point-min)))))

(defun newsticker--treeview-item-show (item feed-name-symbol)
  "Show news ITEM coming from FEED-NAME-SYMBOL in treeview item buffer."
  (setq newsticker--treeview-current-feed (symbol-name feed-name-symbol))
  (with-current-buffer (newsticker--treeview-item-buffer)
    (when (fboundp 'w3m-process-stop)
      (w3m-process-stop (current-buffer)))
    (let ((inhibit-read-only t)
          (is-rendered-HTML nil)
          pos
          (marker1 (make-marker))
          (marker2 (make-marker)))
      (erase-buffer)
      (kill-all-local-variables)
      (remove-overlays)

      (when (and item feed-name-symbol)
        (let ((wwidth (1- (if (window-live-p (newsticker--treeview-item-window))
                              (window-width (newsticker--treeview-item-window))
                            fill-column))))
          (if newsticker-use-full-width
              (setq-local fill-column wwidth))
          (setq-local fill-column (min fill-column wwidth)))
        (let ((desc (newsticker--desc item)))
          (insert "\n" (or desc "[No Description]")))
        (set-marker marker1 (1+ (point-min)))
        (set-marker marker2 (point-max))
        (setq is-rendered-HTML (newsticker--treeview-render-text marker1
                                                                 marker2))
        (when (and newsticker-justification
                   (not is-rendered-HTML))
          (fill-region marker1 marker2 newsticker-justification))

        (newsticker-treeview-item-mode)
        (goto-char (point-min))
        ;; insert logo at top
        (let* ((newsticker-enable-logo-manipulations nil)
               (img (newsticker--image-read feed-name-symbol nil 40)))
          (if (and (display-images-p) img)
              (newsticker--insert-image img (car item))
            (insert (if newsticker-treeview-use-feed-name-from-url-list-in-itemview
                        (symbol-name feed-name-symbol)
                      (newsticker--real-feed-name feed-name-symbol)))))
        (add-text-properties (point-min) (point)
                             (list 'face 'newsticker-feed-face
                                   'mouse-face 'highlight
                                   'help-echo (concat (newsticker--real-feed-name feed-name-symbol)
                                                      "\nClick to visit in web browser.")
                                   :nt-link (newsticker--link item)
                                   'keymap newsticker--treeview-url-keymap))
        (setq pos (point))

        (insert "\n\n")
        ;; insert title
        (setq pos (point))
        (insert (newsticker--title item) "\n")
        (set-marker marker1 pos)
        (set-marker marker2 (point))
        (newsticker--treeview-render-text marker1 marker2)
        (put-text-property pos (point) 'face 'newsticker-treeview-new-face)
        (goto-char marker2)
        (delete-char -1)
        (insert "\n")
        (put-text-property marker2 (point) 'face 'newsticker-treeview-face)
        (set-marker marker2 (point))
        (when newsticker-justification
          (fill-region marker1 marker2 newsticker-justification))
        (goto-char marker2)
        (add-text-properties marker1 (1- (point))
                             (list 'mouse-face 'highlight
                                   'help-echo "Visit in web browser."
                                   :nt-link (newsticker--link item)
                                   'keymap newsticker--treeview-url-keymap))
        (insert (format-time-string newsticker-date-format
                                    (newsticker--time item)))
        (insert "\n")
        (setq pos (point))
        (insert "\n")
        ;; insert enclosures and rest at bottom
        (goto-char (point-max))
        (insert "\n\n")
        (setq pos (point))
        (newsticker--insert-enclosure item newsticker--treeview-url-keymap)
        (put-text-property pos (point) 'face 'newsticker-enclosure-face)
        (setq pos (point))
        (insert "\n")
        (set-marker marker1 pos)
        (newsticker--print-extra-elements item newsticker--treeview-url-keymap t)
        (set-marker marker2 (point))
        (newsticker--treeview-render-text marker1 marker2)
        (put-text-property marker1 marker2 'face 'newsticker-extra-face)
        (goto-char (point-min)))))
  (if (and newsticker-treeview-automatically-mark-displayed-items-as-old
           item
           (memq (newsticker--age item) '(new obsolete)))
      (let ((newsticker-treeview-automatically-mark-displayed-items-as-old nil))
        (newsticker-treeview-mark-item-old t)
        (newsticker--treeview-list-update-faces)))
  (if (window-live-p (newsticker--treeview-item-window))
      (set-window-point (newsticker--treeview-item-window) 1)))

(defun newsticker--treeview-item-update ()
  "Update the treeview item buffer and window."
  (save-excursion
    (if (window-live-p (newsticker--treeview-item-window))
        (set-window-buffer (newsticker--treeview-item-window)
                           (newsticker--treeview-item-buffer)))
    (set-buffer (newsticker--treeview-item-buffer))
    (let ((inhibit-read-only t))
      (erase-buffer))
    (newsticker-treeview-item-mode)))

;; ======================================================================
;;; Tree window
;; ======================================================================
(defun newsticker--treeview-tree-expand (tree)
  "Expand TREE.
Callback function for tree widget that adds nodes for feeds and subgroups."
  (tree-widget-set-theme "folder")
  (let ((group (widget-get tree :nt-group))
        (i 0)
        (nt-id ""))
    (mapcar (lambda (g)
              (setq nt-id (newsticker--treeview-get-id tree i))
              (setq i (1+ i))
              (if (listp g)
                  (let* ((g-name (car g)))
                    `(tree-widget
                      :tag ,(newsticker--treeview-tree-get-tag g-name nil nt-id)
                      :expander newsticker--treeview-tree-expand
                      :expander-p (lambda (&rest ignore) t)
                      :nt-group ,(cdr g)
                      :nt-feed ,g-name
                      :nt-id ,nt-id
                      :leaf-icon newsticker--tree-widget-leaf-icon
                      :keep (:nt-feed :num-new :nt-id :open);;  :nt-group
                      :open nil))
                (let ((tag (newsticker--treeview-tree-get-tag g nil nt-id)))
                `(item :tag ,tag
                       :leaf-icon newsticker--tree-widget-leaf-icon
                       :nt-feed ,g
                       :action newsticker--treeview-list-feed-items
                       :nt-id ,nt-id
                       :keep (:nt-id)
                       :open t))))
            group)))

(defun newsticker--tree-widget-icon-create (icon)
  "Create the ICON widget."
  (let* ((g (widget-get (widget-get icon :node) :nt-feed))
         (ico (and g (newsticker--icon-read (intern g)))))
    (if ico
        (progn
          (widget-put icon :tag-glyph ico)
          (widget-default-create icon)
          ;; Insert space between the icon and the node widget.
          (insert-char ?  1)
          (put-text-property
           (1- (point)) (point)
           'display (list 'space :width tree-widget-space-width)))
      ;; fallback: default icon
      (widget-put icon :leaf-icon 'tree-widget-leaf-icon)
      (tree-widget-icon-create icon))))

(defun newsticker--treeview-tree-expand-status (tree &optional _changed-widget
                                                     _event)
  "Expand the vfeed TREE.
Optional arguments CHANGED-WIDGET and EVENT are ignored."
  (tree-widget-set-theme "folder")
  (list `(item :tag ,(newsticker--treeview-tree-get-tag nil "new")
               :nt-vfeed "new"
               :action newsticker--treeview-list-new-items
               :nt-id ,(newsticker--treeview-get-id tree 0)
               :keep (:nt-id))
        `(item :tag ,(newsticker--treeview-tree-get-tag nil "immortal")
               :nt-vfeed "immortal"
               :action newsticker--treeview-list-immortal-items
               :nt-id ,(newsticker--treeview-get-id tree 1)
               :keep (:nt-id))
        `(item :tag  ,(newsticker--treeview-tree-get-tag nil "obsolete")
               :nt-vfeed "obsolete"
               :action newsticker--treeview-list-obsolete-items
               :nt-id ,(newsticker--treeview-get-id tree 2)
               :keep (:nt-id))
        `(item :tag ,(newsticker--treeview-tree-get-tag nil "all")
               :nt-vfeed "all"
               :action newsticker--treeview-list-all-items
               :nt-id ,(newsticker--treeview-get-id tree 3)
               :keep (:nt-id))))

(defun newsticker--treeview-virtual-feed-p (feed-name)
  "Return non-nil if FEED-NAME is a virtual feed."
  (string-match "\\*.*\\*" feed-name))

(define-widget 'newsticker--tree-widget-leaf-icon 'tree-widget-icon
  "Icon for a tree-widget leaf node."
  :tag        "O"
  :glyph-name "leaf"
  :create 'newsticker--tree-widget-icon-create
  :button-face 'default)

(defun newsticker--treeview-tree-update ()
  "Update treeview tree buffer and window."
  (save-excursion
    (if (window-live-p (newsticker--treeview-tree-window))
        (set-window-buffer (newsticker--treeview-tree-window)
                           (newsticker--treeview-tree-buffer)))
    (set-buffer (newsticker--treeview-tree-buffer))
    (kill-all-local-variables)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (tree-widget-set-theme "folder")
      (setq newsticker--treeview-feed-tree
            (widget-create 'tree-widget
                           :tag (newsticker--treeview-propertize-tag
                                 "Feeds" 0 "feeds")
                           :expander 'newsticker--treeview-tree-expand
                           :expander-p (lambda (&rest _) t)
                           :leaf-icon 'newsticker--tree-widget-leaf-icon
                           :nt-group (cdr newsticker-groups)
                           :nt-id "feeds"
                           :keep '(:nt-id)
                           :open t))
      (setq newsticker--treeview-vfeed-tree
            (widget-create 'tree-widget
                           :tag (newsticker--treeview-propertize-tag
                                 "Virtual Feeds" 0 "vfeeds")
                           :expander 'newsticker--treeview-tree-expand-status
                           :expander-p (lambda (&rest _) t)
                           :leaf-icon 'newsticker--tree-widget-leaf-icon
                           :nt-id "vfeeds"
                           :keep '(:nt-id)
                           :open t))
      (use-local-map widget-keymap)
      (widget-setup))
    (newsticker-treeview-mode)))

(defun newsticker--treeview-propertize-tag (tag &optional num-new nt-id feed
                                                vfeed tooltip)
  "Return propertized copy of string TAG.
Optional argument NUM-NEW is used for choosing face, other
arguments NT-ID, FEED, VFEED and TOOLTIP are added as properties."
  ;;(message "newsticker--treeview-propertize-tag `%s' %s" feed nt-id)
  (let ((face 'newsticker-treeview-face)
        (map (make-sparse-keymap)))
    (if (and num-new (> num-new 0))
        (setq face 'newsticker-treeview-new-face))
    (dolist (key '([mouse-1] [mouse-3]))
      (define-key map key #'newsticker-treeview-tree-click))
    (define-key map "\n" #'newsticker-treeview-tree-do-click)
    (define-key map "\C-m" #'newsticker-treeview-tree-do-click)
    (propertize tag 'face face 'keymap map
                :nt-id nt-id
                :nt-feed feed
                :nt-vfeed vfeed
                'help-echo tooltip
                'mouse-face 'highlight)))

(defun newsticker--treeview-tree-get-tag (feed-name vfeed-name
                                                    &optional nt-id)
  "Return a tag string for either FEED-NAME or, if it is nil, for VFEED-NAME.
Optional argument NT-ID is added to the tag's properties."
  (let (tag tooltip (num-new 0))
    (cond (vfeed-name
           (cond ((string= vfeed-name "new")
                  (setq num-new (newsticker--stat-num-items-total 'new))
                  (setq tag (format "New items (%d)" num-new)))
                 ((string= vfeed-name "immortal")
                  (setq num-new (newsticker--stat-num-items-total 'immortal))
                  (setq tag (format "Immortal items (%d)" num-new)))
                 ((string= vfeed-name "obsolete")
                  (setq num-new (newsticker--stat-num-items-total 'obsolete))
                  (setq tag (format "Obsolete items (%d)" num-new)))
                 ((string= vfeed-name "all")
                  (setq num-new (newsticker--stat-num-items-total))
                  (setq tag (format "All items (%d)" num-new))))
           (setq tooltip tag))
          (feed-name
           (setq num-new (newsticker--stat-num-items-for-group
                          (intern feed-name) 'new 'immortal))
           (setq tag
                 (format "%s (%d)"
                         (if newsticker-treeview-use-feed-name-from-url-list-in-itemview
                             feed-name
                           (newsticker--real-feed-name (intern feed-name)))
                         num-new))
           (setq tooltip
                 (if (newsticker--group-get-group feed-name)
                     tag
                   (format "%s (%d)\n%s"
                           feed-name
                           num-new
                           (newsticker--real-feed-name (intern feed-name)))))))
    (if tag
        (newsticker--treeview-propertize-tag tag num-new
                                             nt-id
                                             feed-name vfeed-name
                                             tooltip))))

(defun newsticker--stat-num-items-for-group (feed-name-symbol &rest ages)
  "Count number of items in feed FEED-NAME-SYMBOL that have an age matching AGES."
  ;;(message "newsticker--stat-num-items-for-group %s %s" feed-name-symbol ages)
  (let ((result (apply #'newsticker--stat-num-items feed-name-symbol ages)))
    (mapc (lambda (f-n)
            (setq result (+ result
                            (apply #'newsticker--stat-num-items (intern f-n)
                                   ages))))
          (newsticker--group-get-feeds
           (newsticker--group-get-group (symbol-name feed-name-symbol)) t))
    result))

(defun newsticker--treeview-count-node-items (feed &optional isvirtual)
  "Count number of relevant items for a treeview node.
FEED gives the name of the feed or group.  If ISVIRTUAL is non-nil
the feed is a virtual feed."
  (let* ((num-new 0))
    (if feed
        (if isvirtual
            (cond ((string= feed "new")
                   (setq num-new (newsticker--stat-num-items-total 'new)))
                  ((string= feed "immortal")
                   (setq num-new (newsticker--stat-num-items-total 'immortal)))
                  ((string= feed "obsolete")
                   (setq num-new (newsticker--stat-num-items-total 'obsolete)))
                  ((string= feed "all")
                   (setq num-new (newsticker--stat-num-items-total))))
          (setq num-new (newsticker--stat-num-items-for-group
                         (intern feed) 'new 'immortal))))
    num-new))

(defun newsticker--treeview-tree-update-tag (w &optional recursive
                                               &rest _ignore)
  "Update tag for tree widget W.
If RECURSIVE is non-nil recursively update parent widgets as
well.  Argument IGNORE is ignored.  Note that this function, if
called recursively, makes w invalid.  You should keep w's nt-id in
that case."
  (let* ((parent (widget-get w :parent))
         (feed (or (widget-get w :nt-feed) (widget-get parent :nt-feed)))
         (vfeed (or (widget-get w :nt-vfeed) (widget-get parent :nt-vfeed)))
         (nt-id (or (widget-get w :nt-id) (widget-get parent :nt-id)))
         (num-new (newsticker--treeview-count-node-items (or feed vfeed)
                                                         vfeed))
         (tag (newsticker--treeview-tree-get-tag feed vfeed nt-id))
         (n (widget-get w :node)))
    (if parent
        (if recursive
            (newsticker--treeview-tree-update-tag parent)))
    (when tag
      (when n
        (widget-put n :tag tag))
      (widget-put w :num-new num-new)
      (widget-put w :tag tag)
      (when (marker-position (widget-get w :from))
        (let ((p (point)))
          ;; FIXME: This moves point!!!!
          (with-current-buffer (newsticker--treeview-tree-buffer)
            (widget-value-set w (widget-value w)))
          (goto-char p))))))

(defun newsticker--treeview-tree-do-update-tags (widget)
  "Actually recursively update tags for WIDGET."
  (save-excursion
    (let ((children (widget-get widget :children)))
      (dolist (w children)
        (newsticker--treeview-tree-do-update-tags w))
      (newsticker--treeview-tree-update-tag widget))))

(defun newsticker--treeview-tree-update-tags (&rest _ignore)
  "Update all tags of all trees.
Arguments are ignored."
  (save-current-buffer
    (set-buffer (newsticker--treeview-tree-buffer))
    (let ((inhibit-read-only t))
      (newsticker--treeview-tree-do-update-tags
       newsticker--treeview-feed-tree)
      (newsticker--treeview-tree-do-update-tags
       newsticker--treeview-vfeed-tree))
      (tree-widget-set-theme "folder")))

(defun newsticker--treeview-tree-update-highlight ()
  "Update highlight in tree buffer."
  (let ((pos (widget-get (newsticker--treeview-get-current-node) :from)))
    (unless (or (integerp pos) (and (markerp pos) (marker-position pos)))
      (setq pos (widget-get (widget-get
                             (newsticker--treeview-get-current-node)
                                        :parent) :from)))
    (when (or (integerp pos) (and (markerp pos) (marker-position pos)))
      (with-current-buffer (newsticker--treeview-tree-buffer)
        (goto-char pos)
        (move-overlay newsticker--tree-selection-overlay
                      (line-beginning-position) (1+ (line-end-position))
                      (current-buffer)))
      (if (window-live-p (newsticker--treeview-tree-window))
          (set-window-point (newsticker--treeview-tree-window) pos)))))

;; ======================================================================
;;; Toolbar
;; ======================================================================
(defvar newsticker-treeview-tool-bar-map
  (when (boundp 'tool-bar-map)
    (defvar tool-bar-map)
    (let ((tool-bar-map (make-sparse-keymap)))
      (tool-bar-add-item "newsticker/prev-feed"
                         'newsticker-treeview-prev-feed
                         'newsticker-treeview-prev-feed
                         :help "Go to previous feed"
                         ;;:enable '(newsticker-previous-feed-available-p) FIXME
                         )
      (tool-bar-add-item "newsticker/prev-item"
                         'newsticker-treeview-prev-item
                         'newsticker-treeview-prev-item
                         :help "Go to previous item"
                         ;;:enable '(newsticker-previous-item-available-p) FIXME
                         )
      (tool-bar-add-item "newsticker/next-item"
                         'newsticker-treeview-next-item
                         'newsticker-treeview-next-item
                         :visible t
                         :help "Go to next item"
                         ;;:enable '(newsticker-next-item-available-p) FIXME
                         )
      (tool-bar-add-item "newsticker/next-feed"
                         'newsticker-treeview-next-feed
                         'newsticker-treeview-next-feed
                         :help "Go to next feed"
                         ;;:enable '(newsticker-next-feed-available-p) FIXME
                         )
      (tool-bar-add-item "newsticker/mark-immortal"
                         'newsticker-treeview-toggle-item-immortal
                         'newsticker-treeview-toggle-item-immortal
                         :help "Toggle current item as immortal"
                         ;;:enable '(newsticker-item-not-immortal-p) FIXME
                         )
      (tool-bar-add-item "newsticker/mark-read"
                         'newsticker-treeview-mark-item-old
                         'newsticker-treeview-mark-item-old
                         :help "Mark current item as read"
                         ;;:enable '(newsticker-item-not-old-p) FIXME
                         )
      (tool-bar-add-item "newsticker/get-all"
                         'newsticker-get-all-news
                         'newsticker-get-all-news
                         :help "Get news for all feeds")
      (tool-bar-add-item "newsticker/update"
                         'newsticker-treeview-update
                         'newsticker-treeview-update
                         :help "Update newsticker buffer")
      (tool-bar-add-item "newsticker/browse-url"
                         'newsticker-browse-url
                         'newsticker-browse-url
                         :help "Browse URL for item at point")
      ;; standard icons / actions
      (define-key tool-bar-map [newsticker-sep-1]
        (list 'menu-item "--double-line"))
      (tool-bar-add-item "close"
                         'newsticker-treeview-quit
                         'newsticker-treeview-quit
                         :help "Close newsticker")
      (tool-bar-add-item "preferences"
                         'newsticker-customize
                         'newsticker-customize
                         :help "Customize newsticker")
      tool-bar-map)))

;; ======================================================================
;;; actions
;; ======================================================================

(defun newsticker-treeview-mouse-browse-url (event)
  "Call `browse-url' for the link of the item at which the EVENT occurred."
  (interactive "e")
  (save-excursion
    (switch-to-buffer (window-buffer (posn-window (event-end event))))
    (let ((url (get-text-property (posn-point (event-end event))
                                  :nt-link)))
      (when url
        (browse-url url)
        (if newsticker-automatically-mark-visited-items-as-old
            (newsticker-treeview-mark-item-old))))))

(defun newsticker-treeview-browse-url ()
  "Call `browse-url' for the link of the item at point."
  (interactive)
  (with-current-buffer (newsticker--treeview-list-buffer)
    (let ((url (get-text-property (point) :nt-link)))
      (when url
        (browse-url url)
        (if newsticker-automatically-mark-visited-items-as-old
            (newsticker-treeview-mark-item-old))))))

(defun newsticker--treeview-buffer-init ()
  "Initialize all treeview buffers."
  (setq newsticker--treeview-buffers nil)
  (add-to-list 'newsticker--treeview-buffers
               (get-buffer-create "*Newsticker Tree*") t)
  (add-to-list 'newsticker--treeview-buffers
               (get-buffer-create "*Newsticker List*") t)
  (add-to-list 'newsticker--treeview-buffers
               (get-buffer-create "*Newsticker Item*") t)

  (unless newsticker--selection-overlay
    (with-current-buffer (newsticker--treeview-list-buffer)
      (setq buffer-undo-list t)
      (setq newsticker--selection-overlay (make-overlay (point-min)
                                                        (point-max)))
      (overlay-put newsticker--selection-overlay 'face
                   'newsticker-treeview-selection-face)))
  (unless newsticker--tree-selection-overlay
    (with-current-buffer (newsticker--treeview-tree-buffer)
      (setq buffer-undo-list t)
      (setq newsticker--tree-selection-overlay (make-overlay (point-min)
                                                             (point-max)))
      (overlay-put newsticker--tree-selection-overlay 'face
                   'newsticker-treeview-selection-face)))

  (newsticker--treeview-tree-update)
  (newsticker--treeview-list-update t)
  (newsticker--treeview-item-update))

(defun newsticker-treeview-update ()
  "Update all treeview buffers and windows.
Note: does not update the layout."
  (interactive)
  (let ((cur-item (newsticker--treeview-get-selected-item)))
    (if (newsticker--group-manage-orphan-feeds)
      (newsticker--treeview-tree-update))
    (newsticker--treeview-list-update t)
    (newsticker--treeview-item-update)
    (newsticker--treeview-tree-update-tags)
    (cond (newsticker--treeview-current-vfeed
           (newsticker--treeview-list-items-with-age
            (intern newsticker--treeview-current-vfeed)))
          (newsticker--treeview-current-feed
           (newsticker--treeview-list-items newsticker--treeview-current-feed)))
    (newsticker--treeview-tree-update-highlight)
    (newsticker--treeview-list-update-highlight)
    (let ((cur-feed (or newsticker--treeview-current-feed
                        newsticker--treeview-current-vfeed)))
      (if (and cur-feed cur-item)
          (newsticker--treeview-list-select cur-item)))))

(defun newsticker-treeview-quit ()
  "Quit newsticker treeview."
  (interactive)
  (setq newsticker--sentinel-callback nil)
  (bury-buffer "*Newsticker Tree*")
  (bury-buffer "*Newsticker List*")
  (bury-buffer "*Newsticker Item*")
  (set-window-configuration newsticker--saved-window-config)
  (when newsticker--frame
    (if (frame-live-p newsticker--frame)
      (delete-frame newsticker--frame))
    (setq newsticker--frame nil))
  (newsticker-treeview-save))

(defun newsticker-treeview-save ()
  "Save treeview group settings."
  (interactive)
  (let ((coding-system-for-write 'utf-8)
        (buf (find-file-noselect (expand-file-name "groups" newsticker-dir))))
    (when buf
      (with-current-buffer buf
        (setq buffer-undo-list t)
        (erase-buffer)
        (insert ";; -*- coding: utf-8 -*-\n")
        (prin1 newsticker-groups (current-buffer) t)
        (save-buffer)
        (kill-buffer)))))

(defun newsticker--treeview-load ()
  "Load treeview settings."
  (let* ((coding-system-for-read 'utf-8)
         (filename (expand-file-name "groups" newsticker-dir))
         (buf (and (file-exists-p filename)
                   (find-file-noselect filename))))
    (when buf
      (set-buffer buf)
      (goto-char (point-min))
      (condition-case nil
          (setq newsticker-groups (read buf))
        (error
         (message "Error while reading newsticker groups file!")
         (setq newsticker-groups nil)))
      (kill-buffer buf))))

(defun newsticker-treeview-scroll-item ()
  "Scroll current item."
  (interactive)
  (save-selected-window
    (select-window (newsticker--treeview-item-window) t)
    (scroll-up 1)))

(defun newsticker-treeview-show-item ()
  "Show current item."
  (interactive)
  (newsticker--treeview-restore-layout)
  (newsticker--treeview-list-update-highlight)
  (with-current-buffer (newsticker--treeview-list-buffer)
    (beginning-of-line)
    (let ((item (get-text-property (point) :nt-item))
          (feed (get-text-property (point) :nt-feed)))
      (newsticker--treeview-item-show item feed)))
  (newsticker--treeview-tree-update-tag
   (newsticker--treeview-get-current-node) t)
  (newsticker--treeview-tree-update-highlight))

(defun newsticker-treeview-next-item ()
  "Move to next item."
  (interactive)
  (newsticker--treeview-restore-layout)
  (save-current-buffer
    (set-buffer (newsticker--treeview-list-buffer))
    (if (newsticker--treeview-list-highlight-start)
        (forward-line 1))
    (if (eobp)
        (forward-line -1)))
  (newsticker-treeview-show-item))

(defun newsticker-treeview-prev-item ()
  "Move to previous item."
  (interactive)
  (newsticker--treeview-restore-layout)
  (save-current-buffer
    (set-buffer (newsticker--treeview-list-buffer))
    (forward-line -1))
  (newsticker-treeview-show-item))

(defun newsticker-treeview-next-new-or-immortal-item (&optional
                                                      current-item-counts
                                                      dont-wrap-trees)
  "Move to next new or immortal item.
Will move to next feed until an item is found.  Will not move if
optional argument CURRENT-ITEM-COUNTS is t and current item is
new or immortal.  Will not move from virtual to ordinary feed
tree or vice versa if optional argument DONT-WRAP-TREES is non-nil."
  (interactive)
  (newsticker--treeview-restore-layout)
  (newsticker--treeview-list-clear-highlight)
  (unless (catch 'found
            (let ((move (not current-item-counts)))
              (while t
                (save-current-buffer
                  (set-buffer (newsticker--treeview-list-buffer))
                  (when move (forward-line 1)
                        (when (eobp)
                          (forward-line -1)
                          (throw 'found nil))))
                (when (memq (newsticker--age
                             (newsticker--treeview-get-selected-item))
                            '(new immortal))
                  (newsticker-treeview-show-item)
                  (throw 'found t))
                (setq move t))))
    (let ((wrap-trees (not dont-wrap-trees)))
      (when (or (newsticker-treeview-next-feed t)
                (and wrap-trees (newsticker--treeview-first-feed)))
        (newsticker-treeview-next-new-or-immortal-item t t)))))

(defun newsticker-treeview-prev-new-or-immortal-item ()
  "Move to previous new or immortal item.
Will move to previous feed until an item is found."
  (interactive)
  (newsticker--treeview-restore-layout)
  (newsticker--treeview-list-clear-highlight)
  (unless (catch 'found
            (while t
              (save-current-buffer
                (set-buffer (newsticker--treeview-list-buffer))
                (when (bobp)
                  (throw 'found nil))
                (forward-line -1))
              (when (memq (newsticker--age
                           (newsticker--treeview-get-selected-item))
                          '(new immortal))
                (newsticker-treeview-show-item)
                (throw 'found t))
                (when (bobp)
                  (throw 'found nil))))
    (when (newsticker-treeview-prev-feed t)
      (set-buffer (newsticker--treeview-list-buffer))
      (goto-char (point-max))
      (newsticker-treeview-prev-new-or-immortal-item))))

(defun newsticker--treeview-get-selected-item ()
  "Return item that is currently selected in list buffer."
  (with-current-buffer (newsticker--treeview-list-buffer)
    (beginning-of-line)
    (get-text-property (point) :nt-item)))

(defun newsticker-treeview-mark-item-old (&optional dont-proceed)
  "Mark current item as old unless it is obsolete.
Move to next item unless DONT-PROCEED is non-nil."
  (interactive)
  (let ((item (newsticker--treeview-get-selected-item)))
    (unless (eq (newsticker--age item) 'obsolete)
      (newsticker--treeview-mark-item item 'old)))
  (unless dont-proceed
    (newsticker-treeview-next-item)))

(defun newsticker-treeview-toggle-item-immortal ()
  "Toggle immortality of current item."
  (interactive)
  (let* ((item (newsticker--treeview-get-selected-item))
         (new-age (if (eq (newsticker--age item) 'immortal)
                      'old
                    'immortal)))
    (newsticker--treeview-mark-item item new-age)
    (newsticker-treeview-next-item)))

(defun newsticker--treeview-mark-item (item new-age)
  "Mark ITEM with NEW-AGE."
  (when item
    (setcar (nthcdr 4 item) new-age)
    ;; clean up ticker FIXME
    )
  (newsticker--cache-save-feed
   (newsticker--cache-get-feed (intern newsticker--treeview-current-feed)))
  (newsticker--treeview-tree-do-update-tags newsticker--treeview-vfeed-tree))

(defun newsticker-treeview-mark-list-items-old ()
  "Mark all listed items as old."
  (interactive)
  (let ((current-feed (or newsticker--treeview-current-feed
                          newsticker--treeview-current-vfeed)))
    (with-current-buffer (newsticker--treeview-list-buffer)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((item (get-text-property (point) :nt-item)))
          (unless (memq (newsticker--age item) '(immortal obsolete))
            (newsticker--treeview-mark-item item 'old)))
        (forward-line 1)))
    (newsticker--treeview-tree-update-tags)
    (if current-feed
        (newsticker-treeview-jump current-feed))))

(defun newsticker-treeview-save-item ()
  "Save current item."
  (interactive)
  (newsticker-save-item (or newsticker--treeview-current-feed
                            newsticker--treeview-current-vfeed)
                        (newsticker--treeview-get-selected-item)))

(defun newsticker-treeview-browse-url-item ()
  "Convert current item to HTML and call `browse-url' on result."
  (interactive)
  (newsticker-browse-url-item (or newsticker--treeview-current-feed
                                  newsticker--treeview-current-vfeed)
                              (newsticker--treeview-get-selected-item)))

(defun newsticker-treeview-customize-current-feed ()
  "Open customization buffer for `newsticker-url-list' and move to current feed."
  (interactive)
  (let ((cur-feed (or newsticker--treeview-current-feed
                      newsticker--treeview-current-vfeed)))
    (if (newsticker--group-get-group cur-feed)
        (message "Cannot customize groups.  Please select a feed.")
      (newsticker-customize-feed cur-feed))))

(defun newsticker--treeview-set-current-node (node)
  "Make NODE the current node."
  (with-current-buffer (newsticker--treeview-tree-buffer)
    (setq newsticker--treeview-current-node-id
          (widget-get node :nt-id))
    (setq newsticker--treeview-current-feed (widget-get node :nt-feed))
    (setq newsticker--treeview-current-vfeed (widget-get node :nt-vfeed))
    (newsticker--treeview-tree-update-highlight)))

(defun newsticker--treeview-get-first-child (node)
  "Get first child of NODE."
  (let ((children (widget-get node :children)))
    (if children
        (car children)
      nil)))

(defun newsticker--treeview-get-second-child (node)
  "Get second child of NODE."
  (let ((children (widget-get node :children)))
    (if children
        (car (cdr children))
      nil)))

(defun newsticker--treeview-get-last-child (node)
  "Get last child of NODE."
  ;;(message "newsticker--treeview-get-last-child %s" (widget-get node :tag))
  (let ((children (widget-get node :children)))
    (if children
        (car (reverse children))
      nil)))

(defun newsticker--treeview-get-feed-vfeed (node)
  "Get (virtual) feed of NODE."
  (or (widget-get node :nt-feed) (widget-get node :nt-vfeed)))

(defun newsticker--treeview-get-next-sibling (node)
  "Get next sibling of NODE."
  (let ((parent (widget-get node :parent)))
    (catch 'found
      (let ((children (widget-get parent :children)))
        (while children
          (if (newsticker--treeview-nodes-eq (car children) node)
              (throw 'found (car (cdr children))))
          (setq children (cdr children)))))))

(defun newsticker--treeview-get-prev-sibling (node)
  "Get previous sibling of NODE."
  (let ((parent (widget-get node :parent)))
    (catch 'found
      (let ((children (widget-get parent :children))
            (prev nil))
        (while children
          (if (and (newsticker--treeview-nodes-eq (car children) node)
                   (widget-get prev :nt-id))
              (throw 'found prev))
          (setq prev (car children))
          (setq children (cdr children)))))))

(defun newsticker--treeview-get-next-uncle (node)
  "Get next uncle of NODE, i.e. parent's next sibling."
  (let* ((parent (widget-get node :parent))
         (grand-parent (widget-get parent :parent)))
    (catch 'found
      (let ((uncles (widget-get grand-parent :children)))
        (while uncles
          (if (newsticker--treeview-nodes-eq (car uncles) parent)
              (throw 'found (car (cdr uncles))))
          (setq uncles (cdr uncles)))))))

(defun newsticker--treeview-get-prev-uncle (node)
  "Get previous uncle of NODE, i.e. parent's previous sibling."
  (let* ((parent (widget-get node :parent))
         (grand-parent (widget-get parent :parent)))
    (catch 'found
      (let ((uncles (widget-get grand-parent :children))
            (prev nil))
        (while uncles
          (if (newsticker--treeview-nodes-eq (car uncles) parent)
              (throw 'found prev))
          (setq prev (car uncles))
          (setq uncles (cdr uncles)))))))

(defun newsticker--treeview-get-other-tree ()
  "Get other tree."
  (if (and (newsticker--treeview-get-current-node)
           (widget-get (newsticker--treeview-get-current-node) :nt-feed))
      newsticker--treeview-vfeed-tree
    newsticker--treeview-feed-tree))

(defun newsticker--treeview-activate-node (node &optional backward)
  "Activate NODE.
If NODE is a tree widget the node's first subnode is activated.
If BACKWARD is non-nil the last subnode of the previous sibling
is activated."
  (newsticker--treeview-set-current-node node)
  (save-current-buffer
    (set-buffer (newsticker--treeview-tree-buffer))
    (cond ((eq (widget-type node) 'tree-widget)
           (unless (widget-get node :open)
             (widget-put node :open nil)
             (widget-apply-action node))
           (newsticker--treeview-activate-node
            (if backward
                (newsticker--treeview-get-last-child node)
              (newsticker--treeview-get-second-child node))))
          (node
           (widget-apply-action node)))))

(defun newsticker--treeview-first-feed ()
  "Jump to the depth-first feed in the `newsticker-groups' tree."
  (newsticker-treeview-jump
   (car (reverse (newsticker--group-get-feeds newsticker-groups t)))))

(defun newsticker-treeview-next-feed (&optional stay-in-tree)
  "Move to next feed.
Optional argument STAY-IN-TREE prevents moving from real feed
tree to virtual feed tree or vice versa.
Return t if a new feed was activated, nil otherwise."
  (interactive)
  (newsticker--treeview-restore-layout)
  (let ((cur (newsticker--treeview-get-current-node))
        (new nil))
    (setq new
          (if cur
              (or (newsticker--treeview-get-next-sibling cur)
                  (newsticker--treeview-get-next-uncle cur)
                  (and (not stay-in-tree)
                       (newsticker--treeview-get-other-tree)))
            (car (widget-get newsticker--treeview-feed-tree :children))))
    (if new
        (progn
          (newsticker--treeview-activate-node new)
          (newsticker--treeview-tree-update-highlight)
          (not (eq new cur)))
      nil)))

(defun newsticker-treeview-prev-feed (&optional stay-in-tree)
  "Move to previous feed.
Optional argument STAY-IN-TREE prevents moving from real feed
tree to virtual feed tree or vice versa.
Return t if a new feed was activated, nil otherwise."
  (interactive)
  (newsticker--treeview-restore-layout)
  (let ((cur (newsticker--treeview-get-current-node))
        (new nil))
    (if cur
      (progn
        (setq new
              (if cur
                  (or (newsticker--treeview-get-prev-sibling cur)
                      (newsticker--treeview-get-prev-uncle cur)
                      (and (not stay-in-tree)
                           (newsticker--treeview-get-other-tree)))
                (car (widget-get newsticker--treeview-feed-tree :children))))
        (if new
            (progn
              (newsticker--treeview-activate-node new t)
              (newsticker--treeview-tree-update-highlight)
              (not (eq new cur)))
          nil))
      nil)))

(defun newsticker-treeview-next-page ()
  "Scroll item buffer."
  (interactive)
  (save-selected-window
    (select-window (newsticker--treeview-item-window) t)
    (condition-case nil
        (scroll-up nil)
      (error
       (goto-char (point-min))))))


(defun newsticker--treeview-unfold-node (feed-name)
  "Recursively show subtree above the node that represents FEED-NAME."
  (let ((node (newsticker--treeview-get-node-of-feed feed-name)))
    (unless node
      (let* ((group-name (car (newsticker--group-find-parent-group
                               feed-name))))
        (newsticker--treeview-unfold-node group-name))
      (setq node (newsticker--treeview-get-node-of-feed feed-name)))
    (when node
      (with-current-buffer (newsticker--treeview-tree-buffer)
        (widget-put node :nt-selected t)
        (widget-apply-action node)
        (newsticker--treeview-set-current-node node)))))

(defun newsticker-treeview-jump (feed-name)
  "Jump to feed FEED-NAME in newsticker treeview."
  (interactive
   (list (let ((completion-ignore-case t))
           (completing-read
            "Jump to feed/group: "
            (append '("new" "obsolete" "immortal" "all")
                    (mapcar #'car (append newsticker-url-list
                                          newsticker-url-list-defaults)))
            nil t))))
  (newsticker--treeview-unfold-node feed-name))

;; ======================================================================
;;; Groups
;; ======================================================================
(defun newsticker--group-do-find-group (feed-or-group-name parent-node node)
  "Recursively find FEED-OR-GROUP-NAME in PARENT-NODE or NODE."
  (cond ((stringp node)
         (when (string= feed-or-group-name node)
           (throw 'found parent-node)))
        ((listp node)
         (cond ((string= feed-or-group-name (car node))
                (throw 'found parent-node))
               ((member feed-or-group-name (cdr node))
                (throw 'found node))
               (t
                (mapc (lambda (n)
                        (if (listp n)
                            (newsticker--group-do-find-group
                             feed-or-group-name node n)))
                      (cdr node)))))))

(defun newsticker--group-find-parent-group (feed-or-group-name)
  "Find group containing FEED-OR-GROUP-NAME."
  (catch 'found
    (mapc (lambda (n)
            (newsticker--group-do-find-group feed-or-group-name
                                             newsticker-groups
                                             n))
          newsticker-groups)
    nil))

(defun newsticker--group-do-get-group (name node)
  "Recursively find group with NAME below NODE."
  (if (string= name (car node))
      (throw 'found node)
    (mapc (lambda (n)
            (if (listp n)
                (newsticker--group-do-get-group name n)))
          (cdr node))))

(defun newsticker--group-get-group (name)
  "Find group with NAME."
  (catch 'found
    (mapc (lambda (n)
            (if (listp n)
                (newsticker--group-do-get-group name n)))
          newsticker-groups)
    nil))

(defun newsticker--group-get-subgroups (group &optional recursive)
  "Return list of subgroups for GROUP.
If RECURSIVE is non-nil recursively get subgroups and return a nested list."
  (let ((result nil))
    (mapc (lambda (n)
            (when (listp n)
              (setq result (cons (car n) result))
              (let ((subgroups (newsticker--group-get-subgroups n recursive)))
                (when subgroups
                  (setq result (append subgroups result))))))
          group)
    result))

(defun newsticker--group-all-groups ()
  "Return nested list of all groups."
  (newsticker--group-get-subgroups newsticker-groups t))

(defun newsticker--group-get-feeds (group &optional recursive)
  "Return list of all feeds in GROUP.
If RECURSIVE is non-nil recursively get feeds of subgroups and
return a nested list."
  (let ((result nil))
    (mapc (lambda (n)
            (if (not (listp n))
                (setq result (cons n result))
              (if recursive
                  (let ((subfeeds (newsticker--group-get-feeds n t)))
                    (when subfeeds
                      (setq result (append subfeeds result)))))))
          (cdr group))
    result))

(defun newsticker-group-add-group (name parent)
  "Add group NAME to group PARENT."
  (interactive
   (list (read-string "Name of new group: ")
         (let ((completion-ignore-case t))
           (completing-read "Name of parent group (optional): " (newsticker--group-all-groups)
                            nil t))))
  (if (newsticker--group-get-group name)
      (error "Group %s exists already" name))
  (let ((p (if (and parent (not (string= parent "")))
               (newsticker--group-get-group parent)
             newsticker-groups)))
    (unless p
      (error "Parent %s does not exist" parent))
    (setcdr p (cons (list name) (cdr p))))
  (newsticker--treeview-tree-update)
  (newsticker-treeview-jump newsticker--treeview-current-feed))

(defun newsticker-group-delete-group (name)
  "Delete group NAME."
  (interactive
   (list (let ((completion-ignore-case t))
           (completing-read "Delete group: "
                            (newsticker--group-names)
                            nil t (car (newsticker--group-find-parent-group
                                        newsticker--treeview-current-feed))))))
  (let ((parent-group (newsticker--group-find-parent-group name)))
    (unless parent-group
      (error "Parent %s does not exist" parent-group))
    (setcdr parent-group (cl-delete-if (lambda (g)
                                         (and (listp g)
                                              (string= name (car g))))
                                       (cdr parent-group)))
    (newsticker--group-manage-orphan-feeds)
    (newsticker--treeview-tree-update)
    (newsticker-treeview-update)
    (newsticker-treeview-jump newsticker--treeview-current-feed)))

(defun newsticker--group-do-rename-group (old-name new-name)
  "Actually rename group OLD-NAME to NEW-NAME."
  (let ((parent-group (newsticker--group-find-parent-group old-name)))
    (unless parent-group
      (error "Parent of %s does not exist" old-name))
    (mapcar (lambda (elt)
              (cond ((and (listp elt)
                          (string= old-name (car elt)))
                     (cons new-name (cdr elt)))
                    (t
                     elt)))
            parent-group)))

(defun newsticker-group-rename-group (old-name new-name)
  "Rename group OLD-NAME to NEW-NAME."
  (interactive
   (list (let* ((completion-ignore-case t))
           (completing-read "Rename group: "
                            (newsticker--group-names)
                            nil t (car (newsticker--group-find-parent-group
                                        newsticker--treeview-current-feed))))
         (read-string "Rename to: ")))
  (setq newsticker-groups (newsticker--group-do-rename-group old-name new-name))
  (newsticker--group-manage-orphan-feeds)
  (newsticker--treeview-tree-update)
  (newsticker-treeview-update)
  (newsticker-treeview-jump newsticker--treeview-current-feed))

(defun newsticker--get-group-names (lst)
  "Do get the group names from LST."
  (delete nil (cons (car lst)
                    (apply #'append
                           (mapcar (lambda (e)
                                     (cond ((listp e)
                                            (newsticker--get-group-names e))
                                           (t
                                            nil)))
                                   (cdr lst))))))

(defun newsticker--group-names ()
  "Get names of all newsticker groups."
  (newsticker--get-group-names newsticker-groups))

(defun newsticker-group-move-feed (name group-name &optional no-update)
  "Move feed NAME to group GROUP-NAME.
Update treeview afterwards unless NO-UPDATE is non-nil."
  (interactive
   (let ((completion-ignore-case t))
     (list (completing-read "Name of feed or group to move: "
                            (append (mapcar #'car newsticker-url-list)
                                    (newsticker--group-names))
                            nil t newsticker--treeview-current-feed)
           (completing-read "Name of new parent group: " (newsticker--group-names)
                            nil t))))
  (let* ((group (if (and group-name (not (string= group-name "")))
                    (newsticker--group-get-group group-name)
                  newsticker-groups))
         (moving-group-p (member name (newsticker--group-names)))
         (moved-thing (if moving-group-p
                          (newsticker--group-get-group name)
                        name)))
    (unless group
      (error "Group %s does not exist" group-name))
    (while (let ((old-group
                  (newsticker--group-find-parent-group name)))
             (when old-group
               (delete moved-thing old-group))
             old-group))
    (setcdr group (cons moved-thing (cdr group)))
    (unless no-update
      (newsticker--treeview-tree-update)
      (newsticker-treeview-update)
      (newsticker-treeview-jump name))))

(defun newsticker-group-shift-feed-down ()
  "Shift current feed down in its group."
  (interactive)
  (newsticker--group-shift 1))

(defun newsticker-group-shift-feed-up ()
  "Shift current feed down in its group."
  (interactive)
  (newsticker--group-shift -1))

(defun newsticker-group-shift-group-down ()
  "Shift current group down in its group."
  (interactive)
  (newsticker--group-shift 1 t))

(defun newsticker-group-shift-group-up ()
  "Shift current group down in its group."
  (interactive)
  (newsticker--group-shift -1 t))

(defun newsticker--group-shift (delta &optional move-group)
  "Shift current feed or group within its parent group.
DELTA is an integer which specifies the direction and the amount
of the shift.  If MOVE-GROUP is nil the currently selected feed
`newsticker--treeview-current-feed' is shifted, if it is t then
the current feed's parent group is shifted.."
  (let* ((cur-feed newsticker--treeview-current-feed)
         (thing (if (and move-group
                         (not (newsticker--group-get-group cur-feed)))
                    (car (newsticker--group-find-parent-group cur-feed))
                  cur-feed))
         (parent-group (newsticker--group-find-parent-group
                        ;;(if move-group (car thing) thing)
                        thing)))
    (unless parent-group
      (error "Group not found!"))
    (let* ((siblings (cdr parent-group))
           (pos (cl-position thing siblings :test
                             (lambda (o1 o2)
                               (equal (if (listp o1) (car o1) o1)
                                      (if (listp o2) (car o2) o2)))))
           (tpos (+ pos delta ))
           (new-pos (max 0 (min (length siblings) tpos)))
           (beg (cl-subseq siblings 0 (min pos new-pos)))
           (end (cl-subseq siblings (+ 1 (max pos new-pos))))
           (p (elt siblings new-pos)))
      (when (not (= pos new-pos))
        (let ((th (or (newsticker--group-get-group thing) thing)))
          (setcdr parent-group
                  (cl-concatenate 'list
                                  beg
                                  (if (> delta 0)
                                      (list p th)
                                    (list th p))
                                  end)))
        (newsticker--treeview-tree-update)
        (newsticker-treeview-update)
        (newsticker-treeview-jump cur-feed)))))

(defun newsticker--count-groups (group)
  "Recursively count number of subgroups of GROUP."
  (let ((result 1))
    (mapc (lambda (g)
            (if (listp g)
                (setq result (+ result (newsticker--count-groups g)))))
          (cdr group))
    result))

(defun newsticker--count-grouped-feeds (group)
  "Recursively count number of feeds in GROUP and its subgroups."
  (let ((result 0))
    (mapc (lambda (g)
            (if (listp g)
                (setq result (+ result (newsticker--count-grouped-feeds g)))
              (setq result (1+ result))))
          (cdr group))
    result))

(defun newsticker--group-remove-obsolete-feeds (group)
  "Recursively remove obsolete feeds from GROUP."
  (let ((result nil)
        (urls (append newsticker-url-list newsticker-url-list-defaults)))
    (mapc (lambda (g)
            (if (listp g)
                (let ((sub-groups
                       (newsticker--group-remove-obsolete-feeds g)))
                  (if sub-groups
                      (setq result (cons sub-groups result))))
              (if (assoc g urls)
                  (setq result (cons g result)))))
          (cdr group))
    (if result
        (cons (car group) (reverse result))
      result)))

(defun newsticker--group-manage-orphan-feeds ()
  "Put unmanaged feeds into `newsticker-groups'.
Remove obsolete feeds as well.
Return t if groups have changed, nil otherwise."
  (unless newsticker-groups
    (setq newsticker-groups '("Feeds")))
  (let ((new-feed nil)
        (grouped-feeds (newsticker--count-grouped-feeds newsticker-groups)))
    (mapc (lambda (f)
            (unless (newsticker--group-find-parent-group (car f))
              (setq new-feed t)
              (newsticker-group-move-feed (car f) nil t)))
          (append newsticker-url-list-defaults newsticker-url-list))
    (setq newsticker-groups
          (newsticker--group-remove-obsolete-feeds newsticker-groups))
    (or new-feed
        (not (= grouped-feeds
                (newsticker--count-grouped-feeds newsticker-groups))))))

;; ======================================================================
;;; Modes
;; ======================================================================
(defun newsticker--treeview-tree-open-menu (event)
  "Open tree menu at position of EVENT."
  (let* ((feed-name newsticker--treeview-current-feed)
         (menu (make-sparse-keymap feed-name)))
    (define-key menu [newsticker-treeview-mark-list-items-old]
      (list 'menu-item "Mark all items old"
            'newsticker-treeview-mark-list-items-old))
    (define-key menu [newsticker-treeview-get-news]
      (list 'menu-item (concat "Get news for " feed-name)
            'newsticker-treeview-get-news))
    (define-key menu [newsticker-get-all-news]
      (list 'menu-item "Get news for all feeds"
            'newsticker-get-all-news))
    (let ((choice (x-popup-menu event menu)))
      (when choice
        (funcall (car choice))))))

(defvar newsticker-treeview-list-menu
  (let ((menu (make-sparse-keymap "Newsticker List")))
    (define-key menu [newsticker-treeview-mark-list-items-old]
      (list 'menu-item "Mark all items old"
            'newsticker-treeview-mark-list-items-old))
    (define-key menu [newsticker-treeview-mark-item-old]
      (list 'menu-item "Mark current item old"
            'newsticker-treeview-mark-item-old))
    (define-key menu [newsticker-treeview-toggle-item-immortal]
      (list 'menu-item "Mark current item immortal (toggle)"
            'newsticker-treeview-toggle-item-immortal))
    (define-key menu [newsticker-treeview-get-news]
      (list 'menu-item "Get news for current feed"
            'newsticker-treeview-get-news))
    menu)
  "Map for newsticker list menu.")

(defvar newsticker-treeview-item-menu
  (let ((menu (make-sparse-keymap "Newsticker Item")))
    (define-key menu [newsticker-treeview-mark-item-old]
      (list 'menu-item "Mark current item old"
            'newsticker-treeview-mark-item-old))
    (define-key menu [newsticker-treeview-toggle-item-immortal]
      (list 'menu-item "Mark current item immortal (toggle)"
            'newsticker-treeview-toggle-item-immortal))
    (define-key menu [newsticker-treeview-get-news]
      (list 'menu-item "Get news for current feed"
            'newsticker-treeview-get-news))
    menu)
  "Map for newsticker item menu.")

(defvar-keymap newsticker-treeview-mode-map
  :doc "Mode map for newsticker treeview."
  "SPC"        #'newsticker-treeview-next-page
  "a"          #'newsticker-add-url
  "b"          #'newsticker-treeview-browse-url-item
  "c"          #'newsticker-treeview-customize-current-feed
  "F"          #'newsticker-treeview-prev-feed
  "f"          #'newsticker-treeview-next-feed
  "g"          #'newsticker-treeview-get-news
  "G"          #'newsticker-get-all-news
  "i"          #'newsticker-treeview-toggle-item-immortal
  "j"          #'newsticker-treeview-jump
  "n"          #'newsticker-treeview-next-item
  "N"          #'newsticker-treeview-next-new-or-immortal-item
  "O"          #'newsticker-treeview-mark-list-items-old
  "o"          #'newsticker-treeview-mark-item-old
  "p"          #'newsticker-treeview-prev-item
  "P"          #'newsticker-treeview-prev-new-or-immortal-item
  "q"          #'newsticker-treeview-quit
  "S"          #'newsticker-treeview-save-item
  "s"          #'newsticker-treeview-save
  "u"          #'newsticker-treeview-update
  "v"          #'newsticker-treeview-browse-url
  ;;"C-j"      #'newsticker-treeview-scroll-item
  ;;"RET"      #'newsticker-treeview-scroll-item
  "M-m"        #'newsticker-group-move-feed
  "M-a"        #'newsticker-group-add-group
  "M-d"        #'newsticker-group-delete-group
  "M-r"        #'newsticker-group-rename-group
  "M-<down>"   #'newsticker-group-shift-feed-down
  "M-<up>"     #'newsticker-group-shift-feed-up
  "M-S-<down>" #'newsticker-group-shift-group-down
  "M-S-<up>"   #'newsticker-group-shift-group-up)

(define-derived-mode newsticker-treeview-mode fundamental-mode "Newsticker TV"
  "Major mode for Newsticker Treeview.
\\{newsticker-treeview-mode-map}"
  (if (boundp 'tool-bar-map)
      (setq-local tool-bar-map
                  newsticker-treeview-tool-bar-map))
  (setq buffer-read-only t
        truncate-lines t))

(define-derived-mode newsticker-treeview-list-mode newsticker-treeview-mode
  "Item List"
  (let ((header (concat
                 (propertize " " 'display '(space :align-to 0))
                 (newsticker-treeview-list-make-sort-button "*" 'sort-by-age)
                 (propertize " " 'display '(space :align-to 2))
                 (if newsticker--treeview-list-show-feed
                     (concat "Feed"
                             (propertize " " 'display '(space :align-to 12)))
                   "")
                 (newsticker-treeview-list-make-sort-button "Date"
                                                            'sort-by-time)
                 (if newsticker--treeview-list-show-feed
                     (propertize " " 'display '(space :align-to 28))
                   (propertize " " 'display '(space :align-to 18)))
                 (newsticker-treeview-list-make-sort-button "Title"
                                                            'sort-by-title))))
    (setq header-line-format header))
  (define-key newsticker-treeview-list-mode-map [down-mouse-3]
    newsticker-treeview-list-menu))

(define-derived-mode newsticker-treeview-item-mode newsticker-treeview-mode
  "Item"
  (define-key newsticker-treeview-item-mode-map [down-mouse-3]
    newsticker-treeview-item-menu))

(defun newsticker-treeview-tree-click (event)
  "Handle click EVENT on a tag in the newsticker tree."
  (interactive "e")
  (newsticker--treeview-restore-layout)
  (save-excursion
    (switch-to-buffer (window-buffer (posn-window (event-end event))))
    (newsticker-treeview-tree-do-click (posn-point (event-end event)) event)))

(defun newsticker-treeview-tree-do-click (&optional pos event)
  "Actually handle click event.
POS gives the position where EVENT occurred."
  (interactive)
  (let* ((pos (or pos (point)))
         (nt-id (get-text-property pos :nt-id))
         (item (get-text-property pos :nt-item)))
    (cond (item
           ;; click in list buffer
           (newsticker-treeview-show-item))
          (t
           ;; click in tree buffer
           (let ((w (newsticker--treeview-get-node-by-id nt-id)))
             (when w
               (newsticker--treeview-tree-update-tag w t t)
               (setq w (newsticker--treeview-get-node-by-id nt-id))
               (widget-put w :nt-selected t)
               (widget-apply w :action event)
               (newsticker--treeview-set-current-node w)
               (and event
                    (eq 'mouse-3 (car event))
                    (sit-for 0)
                    (newsticker--treeview-tree-open-menu event)))))))
  (newsticker--treeview-tree-update-highlight))

(defun newsticker--treeview-restore-layout ()
  "Restore treeview buffers."
  (catch 'error
    (dotimes (i 3)
      (let ((win (nth i newsticker--treeview-windows))
            (buf (nth i newsticker--treeview-buffers)))
        (unless (window-live-p win)
          (newsticker--treeview-window-init)
          (newsticker--treeview-buffer-init)
          (throw 'error t))
        (unless (eq (window-buffer win) buf)
          (set-window-buffer win buf t))))))

(defun newsticker--treeview-frame-init ()
  "Initialize treeview frame."
  (when newsticker-treeview-own-frame
    (unless (and newsticker--frame (frame-live-p newsticker--frame))
      (setq newsticker--frame (make-frame '((name . "Newsticker")))))
    (select-frame-set-input-focus newsticker--frame)
    (raise-frame newsticker--frame)))

(defun newsticker--treeview-window-init ()
  "Initialize treeview windows."
  (setq newsticker--saved-window-config (current-window-configuration))
  (setq newsticker--treeview-windows nil)
  (setq newsticker--treeview-buffers nil)
  (delete-other-windows)
  (split-window-right newsticker-treeview-treewindow-width)
  (add-to-list 'newsticker--treeview-windows (selected-window) t)
  (other-window 1)
  (split-window-below newsticker-treeview-listwindow-height)
  (add-to-list 'newsticker--treeview-windows (selected-window) t)
  (other-window 1)
  (add-to-list 'newsticker--treeview-windows (selected-window) t)
  (other-window 1))

;;;###autoload
(defun newsticker-treeview ()
  "Start newsticker treeview."
  (interactive)
  (newsticker--treeview-load)
  (setq newsticker--sentinel-callback 'newsticker-treeview-update)
  (newsticker--treeview-frame-init)
  (newsticker--treeview-window-init)
  (newsticker--treeview-buffer-init)
  (if (newsticker--group-manage-orphan-feeds)
      (newsticker--treeview-tree-update))
  (newsticker--treeview-set-current-node newsticker--treeview-feed-tree)
  (newsticker-start t) ;; will start only if not running
  (newsticker-treeview-update)
  (newsticker--treeview-item-show-text
   "Newsticker"
   "Welcome to newsticker!"))

(defun newsticker-treeview-get-news ()
  "Get news for current feed."
  (interactive)
  (when newsticker--treeview-current-feed
    (newsticker-get-news newsticker--treeview-current-feed)))

(provide 'newst-treeview)

;;; newst-treeview.el ends here
