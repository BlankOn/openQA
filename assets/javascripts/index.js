function setupIndexPage() {
    $('.timeago').timeago();

    setupFilterForm();
    $('#filter-show-tags').prop('checked', false);
    $('#filter-only-tagged').prop('checked', false);
    $('#filter-fullscreen').prop('checked', false);
    $('#filter-only-tagged').on('change', function() {
        var checked = $('#filter-only-tagged').prop('checked');
        var showTagsElement = $('#filter-show-tags');
        if (checked) {
            showTagsElement.prop('checked', true);
        }
        showTagsElement.prop('disabled', checked);
    });

    parseFilterArguments(function(key, val) {
        if (key === 'show_tags') {
            $('#filter-show-tags').prop('checked', val !== '0');
            return 'show tags';
        } else if (key === 'only_tagged') {
            $('#filter-only-tagged').prop('checked', val !== '0');
            $('#filter-only-tagged').trigger('change');
            return 'only tagged';
        } else if (key === 'group') {
            $('#filter-group').prop('value', val);
            return "group '" + val + "'";
        } else if (key === 'limit_builds') {
            $('#filter-limit-builds').prop('value', val);
            return val + ' builds per group';
        } else if (key === 'time_limit_days') {
            $('#filter-time-limit-days').prop('value', val);
            return val + ' days old or newer';
        } else if (key === 'fullscreen') {
          $('#filter-fullscreen').prop('checked', val !== '0');
          return 'fullscreen';
        }
    });
}

function hideNavbar() {

    var mouseY = 0;
    var navbarHeight = $(".navbar").outerHeight();
    navbarHeight -= 30;

    if ($('#filter-fullscreen').is(':checked')) {
        $("#content").attr('id', 'content_fullscreen');
        $(".navbar").addClass('hidden');
        $(".footer").addClass('hidden');
        $(".jumbotron").addClass('hidden');
        document.addEventListener('mousemove', function(e){
            mouseY = e.clientY || e.pageY;
            if (mouseY < navbarHeight) {
                $(".navbar").removeClass('hidden').addClass('show');
            }
            else if (mouseY > navbarHeight) {
                if (!$("li").hasClass('dropdown open')) {
                    $(".navbar").removeClass('show').addClass('hidden');
                }
            }
        }, false);
    }
};