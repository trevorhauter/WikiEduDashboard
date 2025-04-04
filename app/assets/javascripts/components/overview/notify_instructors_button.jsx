import React from 'react';
import PropTypes from 'prop-types';
import { initiateConfirm } from '../../actions/confirm_actions.js';
import TextAreaInput from '@components/common/text_area_input.jsx';
import { useDispatch, connect } from 'react-redux';
import Loading from '@components/common/loading.jsx';
import TextInput from '@components/common/text_input.jsx';
import { createInstructorAlert } from '../../actions/alert_actions';
import { ALERT_INSTRUCTOR_UPDATE_MESSAGE, ALERT_INSTRUCTOR_UPDATE_SUBJECT, ALERT_INSTRUCTOR_MODAL_HIDDEN, ALERT_INSTRUCTOR_MODAL_VISIBLE, ALERT_INSTRUCTOR_UPDATE_BCC } from '../../constants/alert.js';

const NotifyInstructorsButton = (props) => {
  const { notification, visible } = props;
  const dispatch = useDispatch();

  const sendNotificationHandler = () => {
    dispatch(
      initiateConfirm({
        confirmMessage: I18n.t('course_instructor_notification.confirm_send_notification'),
        onConfirm: () => props.createInstructorAlert({
          courseTitle: props.courseTitle,
          courseId: props.courseId,
          subject: notification.subject,
          message: notification.message,
          bccToSalesforce: notification.bccToSalesforce
        }),
      })
    );
  };

  return (
    <>
      <button onClick={() => dispatch({ type: ALERT_INSTRUCTOR_MODAL_VISIBLE })} className="button">
        {I18n.t('course_instructor_notification.notify_instructors')}
      </button>

      {visible && (
        <div className="basic-modal">
          <button onClick={() => dispatch({ type: ALERT_INSTRUCTOR_MODAL_HIDDEN })} className="pull-right article-viewer-button icon-close" />
          <h2>{I18n.t('course_instructor_notification.notify_instructors')}</h2>
          <p>{I18n.t('course_instructor_notification.notify_instructors_feature_description')}</p>
          <hr />

          {notification.status === 'FAILED' && <div className="notice--error">{notification.error}</div>}

          <TextInput
            placeholder={I18n.t('course_instructor_notification.write_subject')}
            editable
            value={notification.subject}
            onChange={(_, value) => {
              dispatch({ type: ALERT_INSTRUCTOR_UPDATE_SUBJECT, payload: value });
            }}
          />

          <div className="form-group">
            <TextAreaInput
              id="notification-message"
              value={notification.message}
              onChange={(_, value) => {
                dispatch({ type: ALERT_INSTRUCTOR_UPDATE_MESSAGE, payload: value });
              }}
              value_key="notification_message"
              editable
              placeholder={I18n.t('course_instructor_notification.write_message_placeholder')}
            />
          </div>

          <label className="inline-radio">
            { I18n.t('course_instructor_notification.bcc_to_salesforce')}
            <input
              checked={notification.bccToSalesforce}
              className="ml1"
              id="bcc"
              name="bcc"
              onChange={() => dispatch({ type: ALERT_INSTRUCTOR_UPDATE_BCC })}
              type="checkbox"
            />
          </label>

          {notification.status === 'PENDING' ? (
            <Loading text={I18n.t('course_instructor_notification.sending_notification')} />
          ) : (
            <button className="button border pull-right mt1" onClick={sendNotificationHandler}>
              {I18n.t('course_instructor_notification.send_notification_button_text')}
            </button>
          )}
        </div>
      )}
    </>
  );
};

NotifyInstructorsButton.propTypes = {
  courseId: PropTypes.number.isRequired,
  courseTitle: PropTypes.string.isRequired,
};

const mapStateToProps = (state) => {
  return {
    notification: state.instructorAlert,
    visible: state.instructorAlert.modal,
  };
};

export default connect(mapStateToProps, { createInstructorAlert })(NotifyInstructorsButton);
