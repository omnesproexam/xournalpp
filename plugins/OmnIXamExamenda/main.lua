local API_URL =
    "https://exam.self-learning.ch/local/xournalexam/api.php"

local EXAM_FILE_URL =
    "https://exam.self-learning.ch/local/xournalexam/examfile.php"

local SUBMISSION_URL =
    "https://exam.self-learning.ch/local/xournalexam/submission.php"


local examSession = nil


local function showError(message)

    app.openDialog(
        message,
        {"OK"},
        "",
        true
    )

end


local function showInfo(message)

    app.openDialog(
        message,
        {"OK"},
        "",
        false
    )

end


local function extractStartCode(uri)

    if type(uri) ~= "string" then
        return nil
    end

    return string.match(
        uri,
        "[?&]code=([^&]+)"
    )

end


local function redeemStartCode(code)

    local LuaGObject =
        require("LuaGObject")

    local Soup =
        LuaGObject.require(
            "Soup",
            "3.0"
        )

    local GLib =
        LuaGObject.require(
            "GLib",
            "2.0"
        )

    local Json =
        LuaGObject.require(
            "Json",
            "1.0"
        )

    local session =
        Soup.Session()

    session:set_timeout(15)

    local message =
        Soup.Message.new(
            "POST",
            API_URL
        )

    local body =
        "code=" .. code

    local bytes =
        GLib.Bytes.new(body)

    message:set_request_body_from_bytes(
        "application/x-www-form-urlencoded",
        bytes
    )

    local response =
        session:send_and_read(
            message,
            nil
        )

    local data =
        response:get_data()

    if not data then
        error(
            "Moodle hat keine Antwort geliefert."
        )
    end

    local parser =
        Json.Parser.new()

    parser:load_from_data(
        tostring(data),
        -1
    )

    local root =
        parser:get_root()

    if not root then
        error(
            "Die Moodle-Antwort enthält kein gültiges JSON."
        )
    end

    local object =
        root:get_object()

    local success =
        object:get_boolean_member(
            "success"
        )

    if not success then

        local errorcode =
            "unknown"

        local messageText =
            "Unbekannter Moodle-Fehler"

        if object:has_member(
            "errorcode"
        ) then

            errorcode =
                object:get_string_member(
                    "errorcode"
                )

        end

        if object:has_member(
            "message"
        ) then

            messageText =
                object:get_string_member(
                    "message"
                )

        end

        error(
            messageText ..
            "\n\nFehlercode: " ..
            errorcode
        )

    end

    return {

        sessionkey =
            object:get_string_member(
                "sessionkey"
            ),

        userid =
            object:get_int_member(
                "userid"
            ),

        username =
            object:get_string_member(
                "username"
            ),

        user =
            object:get_string_member(
                "user"
            ),

        assignmentid =
            object:get_int_member(
                "assignmentid"
            ),

        cmid =
            object:get_int_member(
                "cmid"
            ),

        assignment =
            object:get_string_member(
                "assignment"
            ),

        sessionexpires =
            object:get_int_member(
                "sessionexpires"
            )

    }

end


local function downloadExamPdf(exam)

    local LuaGObject =
        require("LuaGObject")

    local Soup =
        LuaGObject.require(
            "Soup",
            "3.0"
        )

    local GLib =
        LuaGObject.require(
            "GLib",
            "2.0"
        )

    local session =
        Soup.Session()

    session:set_timeout(30)

    local message =
        Soup.Message.new(
            "POST",
            EXAM_FILE_URL
        )

    local body =
        "sessionkey=" ..
        exam.sessionkey

    local bytes =
        GLib.Bytes.new(body)

    message:set_request_body_from_bytes(
        "application/x-www-form-urlencoded",
        bytes
    )

    local response =
        session:send_and_read(
            message,
            nil
        )

    local headers =
        message:get_response_headers()

    local contentType =
        tostring(
            headers:get_one(
                "Content-Type"
            )
        )

    if not string.find(
        contentType,
        "application/pdf",
        1,
        true
    ) then

        error(
            "Moodle hat keine Aufgaben-PDF geliefert.\n\n" ..
            "Content-Type: " ..
            contentType
        )

    end

    local data =
        response:get_data()

    if not data or
       #data == 0 then

        error(
            "Die heruntergeladene Aufgaben-PDF ist leer."
        )

    end

    if string.sub(
        data,
        1,
        5
    ) ~= "%PDF-" then

        error(
            "Die von Moodle gelieferte Datei ist keine gültige PDF."
        )

    end

    local baseDir =
        GLib.get_user_data_dir()

    local workDir =
        baseDir ..
        "\\MoodleExam\\sessions\\cmid-" ..
        tostring(exam.cmid) ..
        "-user-" ..
        tostring(exam.userid)

    local mkdirResult =
        GLib.mkdir_with_parents(
            workDir,
            448
        )

    if mkdirResult ~= 0 then

        error(
            "Der MoodleExam-Arbeitsordner konnte nicht erstellt werden.\n\n" ..
            workDir
        )

    end

    local pdfPath =
        workDir ..
        "\\exam-source.pdf"

    local file, fileError =
        io.open(
            pdfPath,
            "wb"
        )

    if not file then

        error(
            "Die Aufgaben-PDF konnte nicht gespeichert werden.\n\n" ..
            tostring(fileError)
        )

    end

    file:write(data)
    file:close()

    return {

        path =
            pdfPath,

        workDir =
            workDir,

        size =
            #data

    }

end


local function exportSolutionPdf()

    if not examSession or
       not examSession.workDir then

        error(
            "Es ist keine Prüfung aktiv."
        )

    end

    local solutionPath =
        examSession.workDir ..
        "\\" ..
        examSession.username ..
        "_exam-solution.pdf"

    app.export({

        outputFile =
            solutionPath,

        background =
            "all",

        backend =
            "qpdf"

    })

    local file, fileError =
        io.open(
            solutionPath,
            "rb"
        )

    if not file then

        error(
            "Die Lösungs-PDF konnte nicht gelesen werden.\n\n" ..
            tostring(fileError)
        )

    end

    local data =
        file:read("*a")

    file:close()

    if not data or
       #data < 5 or
       string.sub(
           data,
           1,
           5
       ) ~= "%PDF-" then

        error(
            "Die erzeugte Lösungsdatei ist keine gültige PDF."
        )

    end

    return
        solutionPath,
        data

end


local function uploadSolution(action)

    if not examSession then

        error(
            "Es ist keine Prüfung aktiv."
        )

    end

    local solutionPath, data =
        exportSolutionPdf()

    local LuaGObject =
        require("LuaGObject")

    local Soup =
        LuaGObject.require(
            "Soup",
            "3.0"
        )

    local GLib =
        LuaGObject.require(
            "GLib",
            "2.0"
        )

    local Json =
        LuaGObject.require(
            "Json",
            "1.0"
        )

    local session =
        Soup.Session()

    session:set_timeout(60)

    local message =
        Soup.Message.new(
            "POST",
            SUBMISSION_URL
        )

    local headers =
        message:get_request_headers()

    headers:replace(
        "X-XournalExam-Session",
        examSession.sessionkey
    )

    headers:replace(
        "X-XournalExam-Action",
        action
    )

    local bytes =
        GLib.Bytes.new(data)

    message:set_request_body_from_bytes(
        "application/pdf",
        bytes
    )

    local response =
        session:send_and_read(
            message,
            nil
        )

    local responseData =
        response:get_data()

    if not responseData then

        error(
            "Moodle hat beim Speichern keine Antwort geliefert."
        )

    end

    local parser =
        Json.Parser.new()

    parser:load_from_data(
        tostring(responseData),
        -1
    )

    local root =
        parser:get_root()

    if not root then

        error(
            "Moodle hat keine gültige JSON-Antwort geliefert."
        )

    end

    local object =
        root:get_object()

    local success =
        object:get_boolean_member(
            "success"
        )

    if not success then

        local messageText =
            "Moodle konnte die Prüfung nicht speichern."

        if object:has_member(
            "message"
        ) then

            messageText =
                object:get_string_member(
                    "message"
                )

        end

        error(messageText)

    end

    return {

        path =
            solutionPath,

        status =
            object:get_string_member(
                "status"
            ),

        filename =
            object:get_string_member(
                "filename"
            )

    }

end


function saveExam()

    local ok, result =
        pcall(
            uploadSolution,
            "save"
        )

    if not ok then

        showError(
            "Zwischenspeichern fehlgeschlagen.\n\n" ..
            tostring(result)
        )

        return

    end

    showInfo(
        "Prüfung erfolgreich zwischengespeichert.\n\n" ..
        "Moodle-Datei:\n" ..
        tostring(result.filename)
    )

end


function submitExam()

    if not examSession then

        showError(
            "Es ist keine Prüfung aktiv."
        )

        return

    end

    app.openDialog(

        "Prüfung wirklich abgeben?\n\n" ..
        "Der aktuelle Bearbeitungsstand wird als PDF erzeugt, " ..
        "in Moodle gespeichert und anschließend endgültig abgegeben.",

        {
            "Prüfung abgeben",
            "Abbrechen"
        },

        "confirmSubmitExam",

        false
    )

end


function confirmSubmitExam(button)

    if button ~= 1 then
        return
    end

    local ok, result =
        pcall(
            uploadSolution,
            "submit"
        )

    if not ok then

        showError(
            "Abgabe fehlgeschlagen.\n\n" ..
            tostring(result)
        )

        return

    end

    showInfo(
        "Prüfung erfolgreich abgegeben.\n\n" ..
        "Moodle-Datei:\n" ..
        tostring(result.filename)
    )

end


function onExamUri(uri)

    local code =
        extractStartCode(uri)

    if not code or
       code == "" then

        showError(
            "Ungültiger MoodleExam-Aufruf.\n\n" ..
            "Es wurde kein Startcode gefunden."
        )

        return

    end

    local sessionOk, sessionResult =
        pcall(
            redeemStartCode,
            code
        )

    if not sessionOk then

        showError(
            "Die Prüfung konnte nicht gestartet werden.\n\n" ..
            tostring(sessionResult)
        )

        return

    end

    examSession =
        sessionResult

    local pdfOk, pdfResult =
        pcall(
            downloadExamPdf,
            examSession
        )

    if not pdfOk then

        showError(
            "Die Prüfungssitzung wurde gestartet,\n" ..
            "aber die Aufgaben-PDF konnte nicht geladen werden.\n\n" ..
            tostring(pdfResult)
        )

        return

    end

    examSession.pdfPath =
        pdfResult.path

    examSession.workDir =
        pdfResult.workDir

    local openOk, openResult =
        pcall(
            app.openFile,
            examSession.pdfPath,
            1,
            true
        )

    if not openOk then

        showError(
            "Die Aufgaben-PDF wurde heruntergeladen,\n" ..
            "konnte aber nicht in Xournal++ geöffnet werden.\n\n" ..
            tostring(openResult)
        )

        return

    end

    showInfo(
        "Prüfung erfolgreich gestartet.\n\n" ..

        "Benutzer: " ..
        tostring(examSession.user) .. "\n" ..

        "Username: " ..
        tostring(examSession.username) .. "\n" ..

        "Prüfung: " ..
        tostring(examSession.assignment) .. "\n\n" ..

        "Aufgaben-PDF geladen: " ..
        tostring(pdfResult.size) ..
        " Bytes"
    )

end


function initUi()

    app.registerUi({
        menu =
            "Prüfung zwischenspeichern",
        callback =
            "saveExam"
    })

    app.registerUi({
        menu =
            "Prüfung abgeben",
        callback =
            "submitExam"
    })

end
